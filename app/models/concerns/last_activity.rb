# app/models/concerns/last_activity.rb
#
# ==============================================================================
# LastActivity: 最終利用日時（users.last_active_at）を1日1回だけ記録する
# ==============================================================================
#
# 【このファイルの役割】
#   User に include して、user.touch_last_active! で「今日アプリを使った」ことを記録できるようにする。
#   呼び出しているのは app/controllers/concerns/last_active_tracking.rb（画面を開いたとき）。
#
# 【1日1回だけにする理由（Neon の Compute の節約）】
#   画面を開くたびに UPDATE すると、DB への書き込みがアクセスの数だけ増える。
#   管理画面で知りたいのは「最後に使った日」なので、1日1回で十分。
#   remember_tokens.last_used_at（1日1回だけ延長）と同じ考え方。
#
# 【「1日」の区切り】
#   アプリのタイムゾーン（東京）の0時で区切る。
#   習慣の記録（record_date）は AM4:00 区切りだが、これは「何日の記録か」を決めるためのもの。
#   最終利用日は「いつ使ったか」が分かればよいので、ふつうの0時区切りにしている。
# ==============================================================================
module LastActivity
  extend ActiveSupport::Concern

  # touch_last_active!
  #
  # 【役割】
  #   今日まだ記録していなければ last_active_at を今の時刻にする。
  #   記録した場合は true、何もしなかった場合は false を返す。
  #
  # 【引数 now】
  #   ふだんは省略して Time.current（今の時刻）を使う。テストで時刻を指定できるようにしている。
  #
  # 【① 読み込み済みの値で先に判定する理由】
  #   current_user はリクエストのたびに DB から読み込んでいるので、last_active_at も手元にある。
  #   今日の値ならここで終わるため、2回目以降のアクセスでは SQL が1本も増えない。
  #
  # 【② update_all に WHERE の条件を付ける理由】
  #   本番の Puma は Worker が2つあり、同じ人のリクエストが同時に届くことがある。
  #   「まだ今日の記録がない行だけ更新する」という条件を DB 側で付けることで、
  #   同時に届いても UPDATE が実際に書き込むのは1回だけになる。
  #
  # 【update_all を使う理由】
  #   バリデーション・コールバックを通さず、SQL 1本で更新する。
  #   updated_at も変えないので、updated_at を使っているキャッシュや画面に影響しない。
  def touch_last_active!(now = Time.current)
    start_of_today = now.beginning_of_day
    return false if last_active_at.present? && last_active_at >= start_of_today

    updated_rows = self.class
                       .where(id: id)
                       .where("last_active_at IS NULL OR last_active_at < ?", start_of_today)
                       .update_all(last_active_at: now)
    updated_rows.positive?
  end
end
