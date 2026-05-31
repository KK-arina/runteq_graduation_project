# app/mailers/weekly_report_mailer.rb
#
# ==============================================================================
# WeeklyReportMailer - 週次レポートメール送信クラス
# ==============================================================================
#
# 【このクラスの役割】
#   毎週月曜日 AM9:00（JST）に WeeklyReportJob から呼ばれ、
#   先週の振り返りサマリーをユーザーにメール送信する。
#
# 【親クラス ApplicationMailer について】
#   ApplicationMailer を継承することで以下を自動的に引き継ぐ:
#   - default from: "HabitFlow <onboarding@resend.dev>" （送信元アドレス）
#   - layout "mailer" （HTML メールのレイアウトテンプレート）
#
# ==============================================================================
class WeeklyReportMailer < ApplicationMailer

  # ============================================================
  # helper :application を明示する理由
  # ============================================================
  #
  # ActionMailer はデフォルトでは ApplicationHelper のメソッドを
  # ビューテンプレートに自動インクルードしない場合がある。
  #
  # これがないと app/views/weekly_report_mailer/report.html.erb 内で
  # achievement_color(stat[:rate]) を呼び出した際に
  # ActionView::Template::Error: undefined method `achievement_color'
  # が発生してメールの render に失敗する。
  #
  # helper :application を明示することで ApplicationHelper が
  # 確実にビューに読み込まれ、achievement_color が使えるようになる。
  helper :application

  # ============================================================
  # report メソッド - 週次レポートメールの本体
  # ============================================================
  #
  # 【引数の説明】
  #   user:        User インスタンス（メール送信先ユーザー）
  #   reflection:  WeeklyReflection インスタンス（先週完了済み振り返り、nil 可）
  #   habit_stats: 習慣達成率の配列
  #     [{ name: "毎日読書", rate: 85, completed: 6, target: 7 }, ...]
  #
  # 【habit_stats を Mailer 外で計算して渡す設計にした理由】
  #   Mailer 内での DB アクセスを最小限にすることでテスタビリティが上がる。
  #   テスト時は habit_stats をダミーデータで差し替えられる。
  #
  # 【mail メソッドについて】
  #   ActionMailer の組み込みメソッド。
  #   to / subject を指定するだけでビューファイルが自動的に選ばれる:
  #     HTML 版: app/views/weekly_report_mailer/report.html.erb
  #     テキスト版: app/views/weekly_report_mailer/report.text.erb
  #   両方のビューがあると multipart/alternative 形式で送信される
  #   （HTML 非対応クライアントにはテキスト版が届く）
  #
  def report(user, reflection, habit_stats)
    # ----------------------------------------------------------
    # インスタンス変数をビューに渡す
    # ----------------------------------------------------------
    #
    # 【@ を付けてインスタンス変数にする理由】
    #   ActionMailer のビュー（ERB テンプレート）は
    #   メイラーのインスタンス変数（@xxx）を自動的に参照できる。
    #   ローカル変数（user など）はビューから直接参照できないため
    #   必ず @ を付けてインスタンス変数に代入する。
    @user        = user
    @reflection  = reflection
    @habit_stats = habit_stats

    # ----------------------------------------------------------
    # deep_link_url の生成
    # ----------------------------------------------------------
    #
    # 【new_weekly_reflection_url を使う理由】
    #   タスク要件は deep_link_url = "/weekly_reflections/new" と明記されている。
    #   routes.rb で resources :weekly_reflections, only: [:index, :new, ...] と
    #   定義されているため new_weekly_reflection_url が正しいヘルパー名になる。
    #   weekly_reflections_url は一覧ページ（/weekly_reflections）を指すため誤り。
    #
    # 【_url（絶対 URL）を使う理由】
    #   メールクライアントはアプリのドメインを知らないため
    #   相対パス（/weekly_reflections/new）ではリンクが機能しない。
    #   production.rb の default_url_options で設定したドメインを使って
    #   「https://habitflow.onrender.com/weekly_reflections/new」という
    #   完全な URL を生成する必要がある。
    #
    # 【Rails.application.config から取得する理由】
    #   メイラーのインスタンスメソッドとして定義されている
    #   ActionMailer::Base#default_url_options と混同しないよう
    #   Rails.application.config.action_mailer.default_url_options を
    #   明示的に参照することで環境ごとの設定値を確実に取得できる。
    mailer_url_options = Rails.application.config.action_mailer.default_url_options || {}
    @deep_link_url = new_weekly_reflection_url(
      host:     mailer_url_options[:host]     || "localhost",
      protocol: mailer_url_options[:protocol] || "https"
    )

    # ----------------------------------------------------------
    # 先週の期間ラベル生成
    # ----------------------------------------------------------
    #
    # 【@week_label を生成する理由】
    #   振り返りレコードがある場合はそのラベル（"2026/05/25 - 05/31" 形式）を使う。
    #   ない場合でも「先週（〇月〇日〜〇月〇日）」を生成して
    #   ユーザーが「いつの週のレポートか」を判断できるようにする。
    @week_label = if reflection.present?
                    reflection.week_label
                  else
                    # WeeklyReflection.current_week_start_date は「今週月曜日」を返す
                    # そこから 7 日引いて「先週の月曜日」を取得する
                    last_monday = WeeklyReflection.current_week_start_date - 7.days
                    last_sunday = last_monday + 6.days
                    "#{last_monday.strftime('%Y/%m/%d')} - #{last_sunday.strftime('%m/%d')}"
                  end

    # ----------------------------------------------------------
    # メール送信
    # ----------------------------------------------------------
    #
    # 【to: user.email の安全性について】
    #   WeeklyReportJob 側で where.not(email: nil) によりメールアドレスが
    #   存在するユーザーのみを対象にしているため、ここでは素直に渡す。
    #
    # 【subject の件名フォーマットについて】
    #   【HabitFlow】で始めることでユーザーがメールボックスで
    #   一目で HabitFlow からのメールだと識別できる。
    mail(
      to:      user.email,
      subject: "【HabitFlow】先週（#{@week_label}）の振り返りレポートが届きました"
    )
  end
end