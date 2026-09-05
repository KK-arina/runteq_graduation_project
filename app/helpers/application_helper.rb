# app/helpers/application_helper.rb
#
# ==============================================================================
# ApplicationHelper
# ==============================================================================

module ApplicationHelper

  # rate_hex_color（E-2 修正: 3段階→4段階に変更）
  #
  # 達成率に応じた16進数カラーコードを返す。
  # インラインスタイル（background-color / color）で色を指定する場合に使用する。
  # Tailwind の動的クラス（bg-<%= rate_color %>-500）は
  # ビルド時の静的解析で検出されないため、このメソッドを使う。
  #
  # 【4段階の閾値と対応する Tailwind カラー】
  #   100%以上 → "#22c55e"（green-500:  目標達成）
  #    70%以上 → "#3b82f6"（blue-500:   順調）
  #    40%以上 → "#facc15"（yellow-400: 要改善）
  #    40%未満 → "#f87171"（red-400:    未達成）
  #
  # 【使用箇所】
  #   ダッシュボード / 習慣管理 / 週次振り返り一覧 / 週次振り返り詳細
  #   → 全画面でこのメソッドを参照することで閾値変更時に1箇所の修正で全体反映（DRY）
  def rate_hex_color(rate)
    if rate >= 100
      "#22c55e"   # Tailwind green-500: 目標達成
    elsif rate >= 70
      "#3b82f6"   # Tailwind blue-500:  順調
    elsif rate >= 40
      "#facc15"   # Tailwind yellow-400: 要改善
    else
      "#f87171"   # Tailwind red-400:   未達成
    end
  end

  # ── #I-3 a11y: 達成率「テキスト」用の色（白背景でコントラスト比 AA 4.5:1 以上）──
  #   rate_hex_color は進捗バー（塗り）用の鮮やかな色。これを白背景の「文字」に
  #   使うとコントラスト不足（green-500 約2.2:1 / yellow-400 約1.4:1 等）になり、
  #   Lighthouse のユーザー補助で不合格になる。
  #   そこで文字にはこの濃い版（各色 700 相当）を使い AA を満たす。
  #   バーの色（rate_hex_color）は鮮やかさを保つため変更しない。段階の閾値は
  #   rate_hex_color と揃える（100/70/40）。
  def rate_text_color(rate)
    if rate >= 100
      "#15803d"   # green-700:  目標達成（白背景 約5.0:1）
    elsif rate >= 70
      "#1d4ed8"   # blue-700:   順調（約5.9:1）
    elsif rate >= 40
      "#a16207"   # yellow-700: 要改善（約5.0:1）
    else
      "#b91c1c"   # red-700:    未達成（約5.9:1）
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

  # ============================================================
  # G-2 追加: 週次レポートメール用 達成率カラー返却メソッド
  # ============================================================
  #
  # 【ApplicationHelper に定義する理由】
  #   ActionMailer は helper :application の記述があれば
  #   ApplicationHelper のメソッドをビューで使用できる。
  #   コントローラーのビューとメイラーのビューで共通して使えるよう
  #   ApplicationHelper に1箇所で定義する（DRY 原則）。
  #
  # 【rate_hex_color との違い】
  #   rate_hex_color は4段階（100%/70%/40%/未満）の画面表示用メソッド。
  #   achievement_color はメール向けの3段階（80%/50%/未満）。
  #   メールは簡潔に表現するのが読みやすいため別メソッドとして定義する。
  #
  # 【戻り値】
  #   CSS 16進数色コードの文字列
  #   80%以上 → "#22c55e"（green-500: 達成）
  #   50%以上 → "#3b82f6"（blue-500:  まずまず）
  #   50%未満 → "#f87171"（red-400:   要改善）
  def achievement_color(rate)
    if rate >= 80
      "#22c55e"   # green: 達成
    elsif rate >= 50
      "#3b82f6"   # blue: まずまず
    else
      "#f87171"   # red: 要改善
    end
  end
end