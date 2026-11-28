# ==============================================================================
# users.last_active_at（最終利用日時）を追加するマイグレーション
# ==============================================================================
#
# 【何のためのカラムか】
#   管理画面（/admin）で「最近使わなくなったユーザー」「登録したが使っていないユーザー」を
#   見分けるために、ユーザーが最後にアプリを使った日時を記録する。
#
# 【記録のしかた（このマイグレーションのあとのコミットで実装する）】
#   ログイン中のユーザーが画面を開いたときに、1日1回だけ更新する。
#   remember_tokens.last_used_at と同じく「アクセスのたびには書き込まない」ことで、
#   Neon の Compute（月 100 CU-時間）をほとんど増やさない。
#
# 【def change ではなく up / down に分ける理由】
#   up の中で「既存データから初期値を入れる UPDATE 文」を実行するため。
#   UPDATE 文は Rails が自動で元に戻し方を判断できないので、
#   戻すとき（down）の処理を自分で書く必要がある。
#
# 【このファイルを WSL 側で作った理由】
#   bin/rails generate はコンテナの中で動くため、作られたファイルの持ち主が root になり、
#   WSL 側から書き込めなかった（Permission denied）。
class AddLastActiveAtToUsers < ActiveRecord::Migration[8.1]
  def up
    # ── ① カラムを追加する ─────────────────────────────────────────────
    # datetime: 日付と時刻の両方を記録する型（最終利用の「日」だけでなく時刻も分かる）
    # null を許可する理由: まだ一度も利用の記録がないユーザーは NULL のままにするため
    # comment: DB の中にも説明を残す（Neon の SQL Editor でテーブルを見たときに意味が分かる）
    add_column :users, :last_active_at, :datetime,
               comment: "最後にアプリを利用した日時（管理画面用。1日1回まで更新。管理者自身のアクセスは記録しない）"

    # ── ② 既存のデータから初期値を入れる ─────────────────────────────────
    #
    # 【なぜ初期値を入れるのか】
    #   入れないと、今日より前に使っていたユーザーが全員「記録なし」になり、
    #   休眠ユーザーがすぐには分からないため。
    #
    # 【初期値に使うデータ（ユーザー本人の操作で作られる・更新される日時だけを使う）】
    #   habit_records.updated_at      : 習慣の記録をつけた・付け直した日時
    #   weekly_reflections.created_at : 振り返りを始めた日時
    #   tasks.created_at              : タスクを作った日時
    #   user_purposes.created_at      : 目標（PMVV）を登録した日時
    #   remember_tokens.last_used_at  : ログイン保持でログインした・自動ログインした日時
    #   users.first_login_at          : オンボーディングを通過した日時
    #
    # 【weekly_reflections と tasks で updated_at ではなく created_at を使う理由】
    #   AI 分析のジョブや通知のジョブなど、本人の操作ではない処理で
    #   updated_at が更新される可能性があるため、確実に本人の操作である作成日時を使う。
    #
    # 【GREATEST を使う理由】
    #   PostgreSQL の GREATEST は、渡した値の中でいちばん新しい日時を返す。
    #   NULL（そのテーブルにデータがない）は無視されるので、どれか1つでもあれば値が入る。
    #   すべて NULL の場合だけ NULL になり、WHERE で更新の対象から外す。
    #
    # 【退会済み（deleted_at が NULL でない）ユーザーを対象外にする理由】
    #   管理画面の集計に含めないため、値を入れる必要がない。
    #
    # 【SQL の中に -- のコメントを書かない理由】
    #   .squish が改行をつぶして1行にするため、-- 以降がすべてコメント扱いになり SQL が壊れる。
    #   説明はすべてこの Ruby のコメントに書いている。
    #
    # 【execute を使っても安全な理由】
    #   利用者の入力を一切埋め込まない、固定の SQL 文だから（SQL インジェクションの余地がない）。
    execute <<~SQL.squish
      UPDATE users
      SET last_active_at = activity.last_at
      FROM (
        SELECT u.id,
               GREATEST(
                 (SELECT MAX(hr.updated_at)   FROM habit_records hr      WHERE hr.user_id = u.id),
                 (SELECT MAX(wr.created_at)   FROM weekly_reflections wr WHERE wr.user_id = u.id),
                 (SELECT MAX(t.created_at)    FROM tasks t               WHERE t.user_id  = u.id),
                 (SELECT MAX(up.created_at)   FROM user_purposes up      WHERE up.user_id = u.id),
                 (SELECT MAX(rt.last_used_at) FROM remember_tokens rt    WHERE rt.user_id = u.id),
                 u.first_login_at
               ) AS last_at
        FROM users u
        WHERE u.deleted_at IS NULL
      ) AS activity
      WHERE users.id = activity.id
        AND activity.last_at IS NOT NULL
    SQL
  end

  def down
    # 戻すときはカラムごと削除する（入れた初期値も一緒に消える）
    remove_column :users, :last_active_at
  end
end
