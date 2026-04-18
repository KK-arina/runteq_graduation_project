// app/javascript/controllers/habit_form_controller.js
// =============================================================
// Stimulus コントローラー: 習慣作成フォームの動的切り替えを管理する
// （B-6: カラー・アイコン選択処理を追加、レビュー修正適用）
// （C-6: チェック型の週次目標値フィールドの表示切り替えを追加）
// =============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ===========================================================
  // Targets の定義
  // ===========================================================
  static targets = [
    "measurementType",
    "measurementLabel",
    "unitField",
    "weeklyTargetLabel",
    // C-6 追加: 週次目標値フィールドの表示切り替えに使用するターゲット
    // weeklyTargetField        : 数値型のときだけ表示する入力エリア全体
    // weeklyTargetHiddenWrapper: チェック型のときに weekly_target=7 を送信する hidden input のラッパー
    "weeklyTargetField",
    "weeklyTargetHiddenWrapper",
    "colorInput",
    "colorSwatch",
    "iconInput",
    "iconButton"
  ]

  // ===========================================================
  // connect（ライフサイクル）
  // ===========================================================
  connect() {
    this.toggleUnit()
    this.syncInitialState()
  }

  // ===========================================================
  // syncInitialState（B-6 レビュー修正: 新規追加）
  // ===========================================================
  syncInitialState() {
    if (this.hasColorInputTarget) {
      const currentColor = this.colorInputTarget.value
      this.colorSwatchTargets.forEach(swatch => {
        if (swatch.dataset.colorValue === currentColor) {
          swatch.classList.add("ring-2", "ring-offset-2", "ring-gray-800", "scale-110")
        } else {
          swatch.classList.remove("ring-2", "ring-offset-2", "ring-gray-800", "scale-110")
        }
      })
    }

    if (this.hasIconInputTarget) {
      const currentIcon = this.iconInputTarget.value
      this.iconButtonTargets.forEach(btn => {
        if (btn.dataset.iconValue === currentIcon) {
          btn.classList.add("border-blue-500", "bg-blue-50", "scale-110")
          btn.classList.remove("border-gray-200")
        } else {
          btn.classList.remove("border-blue-500", "bg-blue-50", "scale-110")
          btn.classList.add("border-gray-200")
        }
      })
    }
  }

  // ===========================================================
  // toggleUnit（C-6: 週次目標値フィールドの表示切り替えを追加）
  // ===========================================================
  // 【変更点】
  //   数値型のときだけ weeklyTargetField（入力エリア）を表示する。
  //   チェック型のときは weeklyTargetField を非表示にし、
  //   代わりに weeklyTargetHiddenWrapper（hidden input: value=7）を有効にする。
  //
  //   【なぜ weeklyTargetHiddenWrapper で包むのか】
  //   数値型のときは hidden input が不要なため、
  //   ラッパーを hidden にすることで DOM には残しつつ送信を防げる。
  //   hidden 属性がついた div の中の input は送信されない（HTML の仕様）。
  toggleUnit() {
    const selectedType = this.measurementTypeTargets.find(radio => radio.checked)?.value
    const isNumeric = selectedType === "numeric_type"

    // ── 測定タイプラベルのスタイル切り替え ────────────────────────
    this.measurementLabelTargets.forEach(label => {
      const radio = label.querySelector("input[type='radio']")
      if (radio && radio.checked) {
        label.classList.remove("border-gray-200", "hover:border-gray-300")
        label.classList.add("border-blue-500", "bg-blue-50")
      } else {
        label.classList.remove("border-blue-500", "bg-blue-50")
        label.classList.add("border-gray-200", "hover:border-gray-300")
      }
    })

    // ── 単位フィールドの表示切り替え ─────────────────────────────
    if (isNumeric) {
      this.unitFieldTarget.removeAttribute("hidden")
    } else {
      this.unitFieldTarget.setAttribute("hidden", "")
      const unitInput = this.unitFieldTarget.querySelector("input")
      if (unitInput) unitInput.value = ""
    }

    // ── 週次目標値フィールドの表示切り替え（C-6 追加）──────────────
    // weeklyTargetField ターゲットが存在するときだけ切り替える。
    // edit.html.erb ではこのターゲットを使わない（チェック型は hidden のみ）ため
    // has*** で存在確認してから操作する。
    if (this.hasWeeklyTargetFieldTarget) {
      if (isNumeric) {
        // 数値型: 入力エリアを表示する
        this.weeklyTargetFieldTarget.removeAttribute("hidden")
      } else {
        // チェック型: 入力エリアを非表示にする
        this.weeklyTargetFieldTarget.setAttribute("hidden", "")
      }
    }

    // ── hidden input（weekly_target=7）のラッパーの表示切り替え（C-6 追加）──
    // チェック型のとき: hidden input を有効にして weekly_target=7 を送信する
    // 数値型のとき:     hidden input を無効にして入力エリアの値を送信する
    if (this.hasWeeklyTargetHiddenWrapperTarget) {
      if (isNumeric) {
        // 数値型: hidden input のラッパーを非表示にする（送信しない）
        this.weeklyTargetHiddenWrapperTarget.setAttribute("hidden", "")
      } else {
        // チェック型: hidden input のラッパーを表示して weekly_target=7 を送信する
        this.weeklyTargetHiddenWrapperTarget.removeAttribute("hidden")
      }
    }

    // ── 週次目標値ラベルのテキスト切り替え ───────────────────────
    if (this.hasWeeklyTargetLabelTarget) {
      this.weeklyTargetLabelTarget.textContent = isNumeric
        ? "（単位: 1以上の数値）"
        : "（1〜7回）"
    }

    // ── 週次目標値の max 属性の切り替え ──────────────────────────
    const weeklyTargetInput = this.element.querySelector("input[name='habit[weekly_target]']")
    if (weeklyTargetInput) {
      if (isNumeric) {
        weeklyTargetInput.removeAttribute("max")
      } else {
        weeklyTargetInput.setAttribute("max", "7")
      }
    }
  }

  // ===========================================================
  // selectColor（B-6: レビュー修正適用）
  // ===========================================================
  selectColor(event) {
    const button = event.currentTarget
    const color = button.dataset.colorValue

    this.colorInputTarget.value = color

    this.colorSwatchTargets.forEach(swatch => {
      swatch.classList.remove("ring-2", "ring-offset-2", "ring-gray-800", "scale-110")
    })

    button.classList.add("ring-2", "ring-offset-2", "ring-gray-800", "scale-110")
  }

  // ===========================================================
  // selectIcon（B-6: レビュー修正適用）
  // ===========================================================
  selectIcon(event) {
    const button = event.currentTarget
    const icon = button.dataset.iconValue

    this.iconInputTarget.value = icon

    this.iconButtonTargets.forEach(btn => {
      btn.classList.remove("border-blue-500", "bg-blue-50", "scale-110")
      btn.classList.add("border-gray-200")
    })

    button.classList.remove("border-gray-200")
    button.classList.add("border-blue-500", "bg-blue-50", "scale-110")
  }
}