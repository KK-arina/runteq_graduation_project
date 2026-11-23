# config/initializers/mail_interceptors.rb
#
# ==============================================================================
# メール送信前のインターセプター（送信直前のチェック）の登録
# ==============================================================================
#
# 【なぜ本番だけで登録するのか】
#   テストでは example.com 宛てのメールが送られる（ActionMailer::Base.deliveries に入る）ことを
#   前提にしたテストが多いため、テスト環境で有効にすると既存のテストが壊れる。
#   開発環境では実際には外部へ送らないため、止める必要がない。
#   実際にメールが外部へ送られる本番だけで有効にする。
#
# 【なぜ config.to_prepare の中で登録するのか】
#   ReservedDomainInterceptor は app/ の中のクラスで、Rails が自動で読み込む。
#   起動時の設定（initializers）で app/ のクラスを使うときは、
#   to_prepare の中で使うのが Rails の推奨する安全な方法。
Rails.application.config.to_prepare do
  ActionMailer::Base.register_interceptor(ReservedDomainInterceptor) if Rails.env.production?
end
