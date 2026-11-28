# app/services/admin_user_list_service.rb
#
# ==============================================================================
# AdminUserListService: 管理画面のユーザー一覧（/admin/users）のデータを取り出す
# ==============================================================================
#
# 【このファイルの役割】
#   集計の対象（User.countable_for_usage）のユーザーを、絞り込み・ページ送りをして返す。
#   1人ずつの習慣数・記録数・振り返りの完了数も、同じ SQL の中で数える。
#
# 【N+1 を起こさない工夫】
#   習慣数などを user.habits.count のように1人ずつ数えると、
#   50人なら50回 × 項目の数だけ SQL が走ってしまう（N+1）。
#   そこで SELECT の中に「その人の件数を数えるサブクエリ」を書き、
#   1ページ分を SQL 1本で取り出す（ほかに人数を数える COUNT が1本）。
#
# 【取り出す列を決めている理由】
#   password_digest など、一覧に不要な列（特に秘密の値）を読み込まないため。
#
# 【キャッシュしない理由】
#   名前やメールアドレスを含むため、Solid Cache（DB のテーブル）に複製しない。
#   1ページ50人・SQL 2本なので、キャッシュがなくても負荷は小さい。
#
# 【プライバシー】
#   振り返りのコメント・PMVV・メモなどの入力内容は読まない（件数と「あり／なし」だけ）。
# ==============================================================================
class AdminUserListService
  # 1ページに表示する人数
  PER_PAGE = 50

  # 絞り込みの種類（URL の ?filter= で受け取る。これ以外の値は "all" として扱う）
  FILTERS = %w[all unused dormant active].freeze

  # 「継続中」とみなす日数（最後の利用がこの日数以内）
  ACTIVE_DAYS = 7

  # 「休眠」とみなす日数（記録はあるが、最後の利用がこの日数より前）
  DORMANT_DAYS = 14

  # 一覧に出す列と、1人ずつの件数を数えるサブクエリ
  #
  # 【サブクエリの読み方】
  #   (SELECT COUNT(*) FROM habits h WHERE h.user_id = users.id ...) AS habits_count
  #   → 外側の users の1行ごとに「その人の習慣の数」を数え、habits_count という名前で返す。
  #   EXISTS (SELECT 1 ...) は「1件でもあれば true」を返す（件数を全部数えないので速い）。
  #
  # 【文字列の SQL を使っても安全な理由】
  #   利用者の入力を一切含まない、固定の文字列だから（SQL インジェクションの余地がない）。
  SELECT_COLUMNS = [
    "users.id", "users.name", "users.email", "users.provider",
    "users.created_at", "users.first_login_at", "users.last_active_at",
    "(SELECT COUNT(*) FROM habits h WHERE h.user_id = users.id " \
    "AND h.deleted_at IS NULL AND h.archived_at IS NULL) AS habits_count",
    "(SELECT COUNT(*) FROM habit_records hr WHERE hr.user_id = users.id " \
    "AND hr.deleted_at IS NULL) AS records_count",
    "(SELECT COUNT(*) FROM weekly_reflections wr WHERE wr.user_id = users.id " \
    "AND wr.completed_at IS NOT NULL) AS reflections_count",
    "EXISTS (SELECT 1 FROM user_purposes up WHERE up.user_id = users.id) AS pmvv_registered"
  ].freeze

  # 「記録が1件以上ある」「1件もない」の条件（絞り込みで使う）
  HAS_RECORDS_SQL = "EXISTS (SELECT 1 FROM habit_records hr WHERE hr.user_id = users.id AND hr.deleted_at IS NULL)".freeze
  NO_RECORDS_SQL  = "NOT EXISTS (SELECT 1 FROM habit_records hr WHERE hr.user_id = users.id AND hr.deleted_at IS NULL)".freeze

  # 並び順: 最終利用日の新しい順。最終利用日がない人は最後（NULLS LAST）。
  #   同じ日時の人がいてもページをまたいで順番が入れ替わらないよう、id でも並べる。
  ORDER_SQL = "users.last_active_at DESC NULLS LAST, users.id DESC".freeze

  # 画面に渡す結果をまとめる入れ物
  #   Struct: 名前付きの値をまとめる Ruby の仕組み（result.rows のように取り出せる）
  Result = Struct.new(:rows, :filter, :page, :per_page, :total_count, :total_pages, keyword_init: true)

  # status_for
  #
  # 【役割】1人分の行から、状態（:unused / :active / :cooling / :dormant）を決める。
  #   画面のバッジの表示に使う。絞り込みの SQL と同じ考え方で判定する。
  #     未使用（unused）  : 記録が0件
  #     継続中（active）  : 7日以内に利用
  #     休眠（dormant）   : 記録はあるが、14日より前から利用していない（記録なしも含む）
  #     様子見（cooling） : 上のどれでもない（最後の利用が7〜14日前）
  def self.status_for(row, now: Time.current)
    return :unused if row.records_count.to_i.zero?
    return :active if row.last_active_at.present? && row.last_active_at >= now - ACTIVE_DAYS.days
    return :dormant if row.last_active_at.nil? || row.last_active_at < now - DORMANT_DAYS.days

    :cooling
  end

  # 【引数】
  #   filter   : URL の ?filter= の値。FILTERS にない値（nil や不正な値）は "all" にする
  #   page     : URL の ?page= の値。数字でない・1より小さいときは 1 にする
  #   per_page : 1ページの人数（テストで小さくするために引数にしている）
  #   now      : 今の時刻（テストで時刻を固定できるようにしている）
  def initialize(filter: "all", page: 1, per_page: PER_PAGE, now: Time.current)
    @filter   = FILTERS.include?(filter.to_s) ? filter.to_s : "all"
    @page     = [ page.to_i, 1 ].max
    @per_page = per_page
    @now      = now
  end

  # call
  #
  # 【役割】絞り込み → 人数を数える → 1ページ分を取り出す、の順で実行し、Result を返す。
  #
  # 【ページ番号を最後のページまでに抑える理由】
  #   ?page=999 のように大きすぎる値が来ても、空のページではなく最後のページを出すため。
  def call
    filtered    = apply_filter(User.countable_for_usage)
    total_count = filtered.count
    total_pages = [ (total_count.to_f / @per_page).ceil, 1 ].max
    page        = [ @page, total_pages ].min

    rows = filtered.select(SELECT_COLUMNS)
                   .order(Arel.sql(ORDER_SQL))
                   .limit(@per_page)
                   .offset((page - 1) * @per_page)
                   .to_a

    Result.new(rows: rows, filter: @filter, page: page, per_page: @per_page,
               total_count: total_count, total_pages: total_pages)
  end

  private

  # apply_filter: 絞り込みの種類に合わせて、条件を足す
  def apply_filter(relation)
    case @filter
    when "unused"
      relation.where(NO_RECORDS_SQL)
    when "dormant"
      relation.where(HAS_RECORDS_SQL)
              .where("users.last_active_at IS NULL OR users.last_active_at < ?", @now - DORMANT_DAYS.days)
    when "active"
      relation.where(last_active_at: (@now - ACTIVE_DAYS.days)..)
    else
      relation
    end
  end
end
