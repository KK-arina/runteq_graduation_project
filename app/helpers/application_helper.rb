# app/helpers/application_helper.rb
#
# ==============================================================================
# ApplicationHelper
# ==============================================================================

module ApplicationHelper
  # rate_color（C-6 追加）
  # 達成率に応じた色名（"green"/"blue"/"red"）を返す。
  # Tailwind の動的クラス生成では CSS が生成されないため、
  # このメソッドは rate_hex_color と組み合わせてインラインスタイルで使う。
  def rate_color(rate)
    if rate >= 80
      "green"
    elsif rate >= 50
      "blue"
    else
      "red"
    end
  end

  # rate_hex_color（C-6 追加）
  # 達成率に応じた16進数カラーコードを返す。
  # インラインスタイル（background-color / color）で色を指定する場合に使用する。
  # Tailwind の動的クラス（bg-<%= rate_color %>-500）は
  # ビルド時の静的解析で検出されないため、このメソッドを使う。
  #
  # 【戻り値】
  #   "#22c55e"（緑: 80%以上）/ "#60a5fa"（青: 50〜79%）/ "#f87171"（赤: 未満）
  def rate_hex_color(rate)
    if rate >= 80
      "#22c55e"
    elsif rate >= 50
      "#60a5fa"
    else
      "#f87171"
    end
  end

  # habit_progress_text（C-6 追加）
  # 習慣の進捗テキストを返す。
  # ダッシュボード・週次振り返り・習慣管理で同じ表記を使うためのヘルパー。
  #
  # 【表記の統一ルール】
  #   チェック型: 「完了数 / 目標日数日（達成率%）」
  #     分母は effective_weekly_target（除外日を考慮した実際の目標日数）を使う。
  #     weekly_target（設定上の目標値）ではなく除外日考慮後の値を使うことで
  #     習慣管理の表記と一致する。
  #     単位は「日」（やった日数を記録するため）。
  #
  #   数値型: 「実績値 / 目標値 単位（達成率%）」
  #     分母は weekly_target（週の目標数値）を使う。
  #     単位は habit.unit（例: 冊、分、km）。unit が空の場合は「回」。
  #
  # 【引数】
  #   habit: Habit インスタンス
  #   stats: { rate:, completed_count:, numeric_sum:, effective_target: } のハッシュ
  #          DashboardsController / HabitsController が計算して渡す
  #
  # 【使用例】
  #   <%= habit_progress_text(habit, stats) %>
  def habit_progress_text(habit, stats)
    if habit.check_type?
      # effective_weekly_target: 除外日を考慮した実際の目標日数
      # 例: 週7日設定・土日除外 → effective_weekly_target = 5
      "#{stats[:completed_count]}/#{habit.effective_weekly_target}日（#{stats[:rate]}%）"
    else
      numeric_sum = format("%g", (stats[:numeric_sum] || 0).to_f.round(1))
      unit        = habit.unit.presence || "回"
      "#{numeric_sum}/#{habit.weekly_target}#{unit}（#{stats[:rate]}%）"
    end
  end
end