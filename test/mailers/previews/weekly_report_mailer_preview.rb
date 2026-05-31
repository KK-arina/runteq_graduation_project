# test/mailers/previews/weekly_report_mailer_preview.rb
#
# ==============================================================================
# WeeklyReportMailerPreview - ブラウザでのメール目視確認用
# ==============================================================================
#
# 【アクセス方法】
#   http://localhost:3000/rails/mailers/weekly_report_mailer/report
#
# 【このファイルの役割】
#   実際にメールを送信せずにブラウザでレンダリング結果を確認できる。
#   「デザイン崩れ」「achievement_color の NoMethodError」を事前に防ぐ。
# ==============================================================================
class WeeklyReportMailerPreview < ActionMailer::Preview

  def report
    # DB に保存しないダミーユーザー
    user = User.new(name: "テスト太郎", email: "test@example.com")

    # DB に保存しないダミー振り返り
    reflection = WeeklyReflection.new(
      direct_reason:        "先週は体調を崩してしまい後半の継続が難しかった。",
      background_situation: "早寝早起きの習慣が乱れたことが直接の原因。",
      next_action:          "今週は23時までに布団に入ることを徹底する。",
      reflection_comment:   "今週から気持ちを切り替えて頑張ります！",
      mood:                 4
    )
    # week_label メソッドをダミー文字列を返すように上書きする
    reflection.define_singleton_method(:week_label) { "2026/05/25 - 05/31" }

    # 3段階カラー（緑・青・赤）が全て表示されるようなダミーデータ
    habit_stats = [
      { name: "朝の読書（30分）",      rate: 100, completed: 7, target: 7 },  # 緑
      { name: "ジムでの筋トレ",        rate:  60, completed: 3, target: 5 },  # 青
      { name: "英語リスニング（20分）", rate:  28, completed: 2, target: 7 }  # 赤
    ]

    WeeklyReportMailer.report(user, reflection, habit_stats)
  end
end