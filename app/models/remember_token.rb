# app/models/remember_token.rb
#
# ==============================================================================
# RememberToken（ログイン保持トークン）モデル
# ==============================================================================
#
# 【このモデルの役割】
#   「ログインしたままにする」にチェックしてログインした端末ごとに1行作られる。
#   ブラウザの Cookie には「生のトークン」、DB には「その SHA-256 値」だけを保存し、
#   セッションが切れたときに Cookie のトークンと照合して自動ログインする。
#
# 【保持期間の考え方】
#   ・使うたびに延びる30日（IDLE_TIMEOUT）
#       → 30日間まったく使わなければ失効する
#   ・最初の発行から最長180日（ABSOLUTE_LIFETIME）
#       → 毎日使っていても180日で必ず再ログインを求める
#         （Cookie が盗まれた場合に、無期限に悪用され続けるのを防ぐ）
#
# 【DB への書き込みを増やさない工夫】
#   ・自動ログインはセッションが切れたときだけ動く（普段のページ表示では動かない）
#   ・期限の延長は「前回の延長から1日以上たっているとき」だけ行う（SLIDE_INTERVAL）
#   → Neon の Compute（月 100 CU-時間）をほとんど消費しない
# ==============================================================================
class RememberToken < ApplicationRecord
  # ============================================================
  # 定数（期間などの設定値）
  # ============================================================
  #
  # 【定数にする理由】
  #   数字をコードのあちこちに直接書くと、変更時に修正漏れが起きる。
  #   ここだけ変えれば全体に反映されるようにしておく。

  # 使わなかった場合に失効するまでの期間（使うたびにここまで延長される）
  IDLE_TIMEOUT = 30.days

  # 最初の発行から、どれだけ延長しても超えられない上限
  ABSOLUTE_LIFETIME = 180.days

  # 期限を延長する最小間隔（この間隔より短い再利用では DB に書き込まない）
  SLIDE_INTERVAL = 1.day

  # 1ユーザーが同時に「ログインしたまま」にできる端末数の上限
  #   これを超えたら古いものから削除し、行が増え続けないようにする
  MAX_PER_USER = 10

  # ============================================================
  # アソシエーション・バリデーション
  # ============================================================

  # belongs_to :user
  #   remember_tokens.user_id から User を取得できるようにする。
  #   Rails 5 以降、belongs_to は「user が存在すること」を自動で検証する。
  belongs_to :user

  # presence: 空のまま保存されないようにする（DB の null: false と二重の守り）
  #
  # 【uniqueness バリデーションを書かない理由】
  #   uniqueness を書くと、保存のたびに「同じ値があるか」を確認する SELECT が増える。
  #   token_digest は256ビットの乱数から作るので重複は事実上起こらず、
  #   万一の重複も DB のユニークインデックスが防ぐため、余計なクエリを省く。
  validates :token_digest, :expires_at, :last_used_at, presence: true

  # ============================================================
  # スコープ（よく使う検索条件に名前を付けたもの）
  # ============================================================

  # active: まだ期限が切れていないトークン
  #   where.not(expires_at: ..Time.current) は「expires_at が今以下ではない」
  #   ＝「expires_at が今より後」という意味。
  #   ハッシュで書くとテーブル名付きの SQL になるため、
  #   users と JOIN したときにもカラム名があいまいにならない。
  #   lambda（-> { }）で書く理由: Time.current を呼び出しのたびに評価させるため。
  scope :active, -> { where.not(expires_at: ..Time.current) }

  # expired: すでに期限が切れたトークン（掃除用）
  scope :expired, -> { where(expires_at: ..Time.current) }

  # ============================================================
  # クラスメソッド
  # ============================================================

  # digest
  #
  # 【役割】生のトークンを SHA-256 で変換して、DB に保存する形にする。
  #
  # 【パスワードのように bcrypt を使わない理由】
  #   パスワードは人が考えた短い文字列なので、総当たりされにくい遅いハッシュ（bcrypt）が必要。
  #   このトークンは SecureRandom で作った256ビットの乱数で、総当たりは事実上不可能。
  #   さらに SHA-256 なら「同じ入力 → 必ず同じ値」になるので、
  #   digest をそのまま DB で検索でき、インデックスが効いて1回の SELECT で済む。
  #   （bcrypt は毎回ソルトが変わるため、この検索ができない）
  #
  # .to_s: nil が渡されても例外にせず空文字として扱うため
  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end

  # issue_for!
  #
  # 【役割】
  #   指定ユーザーに新しいトークンを発行して DB に保存し、
  #   [保存したレコード, 生のトークン] の2つを返す。
  #   生のトークンは Cookie に入れるためだけに使い、DB には保存しない。
  #
  # 【SecureRandom.urlsafe_base64(32) を使う理由】
  #   32バイト（256ビット）の暗号論的に安全な乱数を作り、
  #   Cookie に入れても問題のない文字（英数字と - _）だけの文字列にする。
  #   OWASP は「最低128ビット」を推奨しており、それを十分に上回る。
  #
  # 【トランザクションで囲む理由】
  #   「期限切れの掃除 → 新規作成 → 上限超過分の削除」を一体で行い、
  #   途中で失敗したときに中途半端な状態が残らないようにする。
  #   プロジェクトの作法（#A-7）に合わせて ApplicationRecord.with_transaction を使う。
  def self.issue_for!(user)
    raw_token = SecureRandom.urlsafe_base64(32)
    now       = Time.current
    record    = nil

    ApplicationRecord.with_transaction do
      # ① このユーザーの期限切れトークンを削除する
      #   ログインのタイミング（もともと DB に書き込む場面）でまとめて掃除するため、
      #   定期実行のジョブ（cron）を用意しなくても行が溜まらない。
      #   delete_all: 1本の DELETE 文で消す（1行ずつ読み込まないので速い）
      where(user_id: user.id).expired.delete_all

      # ② 新しいトークンを保存する（DB には digest だけ）
      record = create!(
        user:         user,
        token_digest: digest(raw_token),
        expires_at:   now + IDLE_TIMEOUT,
        last_used_at: now
      )

      # ③ 端末数の上限（10台）を超えた古いトークンを削除する
      prune_excess_for!(user)
    end

    [record, raw_token]
  end

  # find_active_by_raw_token
  #
  # 【役割】Cookie から取り出した生のトークンで、有効なトークンを1件探す。
  #
  # 【eager_load(:user) を使う理由】
  #   トークンを見つけたあと必ず user も使うため、
  #   JOIN で1回の SQL にまとめて取得する（SQL が2回に分かれない）。
  #
  # 【空のときに DB を見ない理由】
  #   改ざん・期限切れの Cookie は復号の段階で nil になる。
  #   その場合は DB に問い合わせず、すぐに nil を返して負荷を増やさない。
  def self.find_active_by_raw_token(raw_token)
    return nil if raw_token.blank?

    active.eager_load(:user).find_by(token_digest: digest(raw_token))
  end

  # prune_excess_for!
  #
  # 【役割】1ユーザーのトークンが MAX_PER_USER（10）件を超えたら、古いものから削除する。
  #
  # order(created_at: :desc, id: :desc) で新しい順に並べ、
  # offset(MAX_PER_USER) で「新しい10件を飛ばした残り」= 古いもののIDだけを取得する。
  # id も並び順に入れる理由: 同じ秒に作られた行があっても順番が必ず決まるようにするため。
  def self.prune_excess_for!(user)
    stale_ids = where(user_id: user.id)
                  .order(created_at: :desc, id: :desc)
                  .offset(MAX_PER_USER)
                  .pluck(:id)

    where(id: stale_ids).delete_all if stale_ids.any?
  end

  # ============================================================
  # インスタンスメソッド
  # ============================================================

  # absolute_expires_at
  #
  # 【役割】このトークンが「どれだけ延長しても超えられない期限」を返す。
  #   最初に発行された日時（created_at）+ 180日。
  def absolute_expires_at
    created_at + ABSOLUTE_LIFETIME
  end

  # slide_expiration!
  #
  # 【役割】
  #   自動ログインで使われたときに、有効期限を「今から30日後」に延長する。
  #   ただし最長180日の上限は超えない。
  #
  # 【戻り値】
  #   true  : 延長した（呼び出し側で Cookie の期限も更新する）
  #   false : 前回から1日たっていないので何もしなかった
  #
  # 【1日に1回だけ書き込む理由】
  #   複数タブの復元などで短時間に何度も自動ログインが起きても、
  #   毎回 UPDATE しないようにして Neon の Compute を節約する。
  #
  # 【update_columns を使う理由】
  #   バリデーションやコールバックを通さず、指定カラムだけを1本の UPDATE で更新する。
  #   update_columns は updated_at を自動更新しないため、明示的に入れている。
  def slide_expiration!
    now = Time.current
    return false if last_used_at > now - SLIDE_INTERVAL

    # [今から30日後, 最長期限].min → 2つのうち早いほうを新しい期限にする
    new_expires_at = [now + IDLE_TIMEOUT, absolute_expires_at].min

    update_columns(expires_at: new_expires_at, last_used_at: now, updated_at: now)
    true
  end
end