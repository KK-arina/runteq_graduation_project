require "active_support/core_ext/integer/time"

# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with Cache-Control for performance.
  config.public_file_server.headers = { "Cache-Control" => "public, max-age=#{1.hour.to_i}" }

  # Show full error reports and disable caching.
  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  # Disable caching for Action Mailer templates even if Action Controller
  # caching is enabled.
  config.action_mailer.perform_caching = false

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Unlike controllers, the mailer instance doesn't have any context about the
  # incoming request so you'll need to provide the :host parameter yourself.
  config.action_mailer.default_url_options = { host: "www.example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Raise exceptions for disallowed deprecations.
  config.active_support.disallowed_deprecation = :raise

  # Tell Active Support which deprecation messages to disallow.
  config.active_support.disallowed_deprecation_warnings = []

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  # ============================================================
  # Issue #A-3: テスト環境の GoodJob 設定
  # ============================================================
  #
  # 【なぜ :test にするのか】
  #
  # Rails の ActiveJob には以下のアダプターモードがある:
  #
  # :async   → 非同期スレッドで実行。サーバー再起動でジョブが消える。開発向け。
  # :inline  → perform_later を呼んだ瞬間に同期実行。即時副作用が発生する。
  # :test    → ジョブを「実行せずキューに積むだけ」にする。テスト向け。← これを採用
  # :good_job → PostgreSQL 経由で非同期実行。開発・本番向け。
  #
  # 【:test を採用する理由】
  #
  # :inline は「perform_later を呼んだ瞬間に処理が走る」ため、
  # テスト中に意図しない副作用（メール送信・DB更新）が発生しやすい。
  # 特に複数ジョブが連鎖する場合にテストが不安定になる。
  #
  # :test は「積まれたことの確認」と「意図的な実行」を分離できる:
  #
  #   # ジョブが積まれたことだけを確認するテスト
  #   assert_enqueued_with(job: MonthlyAiCountResetJob) do
  #     UserSetting.trigger_reset
  #   end
  #
  #   # 明示的にジョブを実行してから結果を確認するテスト
  #   perform_enqueued_jobs do
  #     MonthlyAiCountResetJob.perform_later
  #   end
  #   assert_equal 0, UserSetting.first.ai_analysis_count
  #
  # この「積む」と「動かす」の分離がテストの安定性を大幅に向上させる。
  config.active_job.queue_adapter = :test
end
