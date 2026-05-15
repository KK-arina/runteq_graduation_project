// app/javascript/controllers/habit_form_controller.js
// =============================================================
// Stimulus コントローラー: 習慣作成フォームの動的切り替えを管理する
// （E-2 修正: toggleUnit を Stimulus targets から querySelector ベースに変更）
// =============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "measurementType",
    "measurementLabel",
    "unitField",
    "weeklyTargetLabel",
    "weeklyTargetField",
    "weeklyTargetInput",
    "colorInput",
    "colorSwatch",
    "iconInput",
    "iconButton"
  ]

  connect() {
    this.toggleUnit()
    this.syncInitialState()
  }

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

  toggleUnit() {
    // ── querySelector ベースに変更する理由 ─────────────────────────
    // Stimulus の targets は DOM の読み込みタイミングによって
    // 正しく取得できないケースがあった。
    // element（フォーム要素）から直接 querySelector で取得することで
    // 確実に対象要素を操作できる。
    // ───────────────────────────────────────────────────────────────
    const form = this.element

    const selectedType = this.measurementTypeTargets.find(r => r.checked)?.value
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
    const unitField = form.querySelector("[data-habit-form-target='unitField']")
    if (unitField) {
      if (isNumeric) {
        unitField.removeAttribute("hidden")
      } else {
        unitField.setAttribute("hidden", "")
        const unitInput = unitField.querySelector("input")
        if (unitInput) unitInput.value = ""
      }
    }

    // ── 週次目標値フィールドの表示切り替え ───────────────────────
    // 【設計方針】
    //   number_field 1つで管理する（hidden input 廃止）。
    //   チェック型: フィールドを非表示にして value=7 に固定する。
    //   数値型:     フィールドを表示してユーザー入力値をそのまま送信する。
    const weeklyTargetField = form.querySelector("[data-habit-form-target='weeklyTargetField']")
    const weeklyTargetInput = form.querySelector("[data-habit-form-target='weeklyTargetInput']")

    if (weeklyTargetField) {
      if (isNumeric) {
        // 数値型: フィールドを表示する
        weeklyTargetField.removeAttribute("hidden")
        if (weeklyTargetInput) {
          weeklyTargetInput.removeAttribute("max")
          // ── E-3 修正: デフォルト値を 5 → 7 に変更する ─────────────────
          // 変更前: 値が未入力または7（チェック型デフォルト）の場合は5にリセット
          // 変更後: 値が未入力の場合のみ7にリセット
          //
          // 【変更理由】
          //   チェック型のデフォルトが7なのに、数値型に切り替えると5になる
          //   という不整合をなくす。新規登録フォームのデフォルトを7に統一する。
          //   ユーザーが自分で値を入力した場合（"7"以外）はそのまま維持する。
          if (!weeklyTargetInput.value) {
          weeklyTargetInput.value = 7
          }
          // ────────────────────────────────────────────────────────────────
        }
      } else {
        // チェック型: フィールドを非表示にして value=7 に固定する
        weeklyTargetField.setAttribute("hidden", "")
        if (weeklyTargetInput) {
          weeklyTargetInput.value = 7
          weeklyTargetInput.setAttribute("max", "7")
        }
      }
    }

    // ── 週次目標値ラベルのテキスト切り替え ───────────────────────
    const weeklyTargetLabel = form.querySelector("[data-habit-form-target='weeklyTargetLabel']")
    if (weeklyTargetLabel) {
      weeklyTargetLabel.textContent = isNumeric ? "（単位: 1以上の数値）" : "（1〜7回）"
    }
  }

  selectColor(event) {
    const button = event.currentTarget
    const color = button.dataset.colorValue

    this.colorInputTarget.value = color

    this.colorSwatchTargets.forEach(swatch => {
      swatch.classList.remove("ring-2", "ring-offset-2", "ring-gray-800", "scale-110")
    })

    button.classList.add("ring-2", "ring-offset-2", "ring-gray-800", "scale-110")
  }

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