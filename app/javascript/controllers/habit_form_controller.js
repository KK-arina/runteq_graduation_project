// app/javascript/controllers/habit_form_controller.js
// =============================================================
// Stimulus コントローラー: 習慣作成フォームの動的切り替えを管理する
// （E-2 修正: toggleUnit を Stimulus targets から querySelector ベースに変更）
//
// 【アクセシビリティ修正での変更】
//   カラー・アイコンのボタンの「選択中」の状態を、見た目（枠線の色）だけでなく
//   aria-pressed 属性（"true" / "false"）でも切り替えるようにした。
//   スクリーンリーダーは aria-pressed="true" のボタンを「押されています」と読み上げるため、
//   画面が見えない人にも、どの色・アイコンが選ばれているかが伝わる。
//   見た目と aria-pressed を必ず同時に変えるため、共通メソッド
//   markColorSwatch / markIconButton にまとめている。
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

  // syncInitialState: 画面表示時に、hidden の値と各ボタンの状態をそろえる
  //   ブラウザの「戻る」で表示されたときなど、hidden の値とボタンの見た目が
  //   ずれていても、ここで正しい状態に直す。
  syncInitialState() {
    if (this.hasColorInputTarget) {
      const currentColor = this.colorInputTarget.value
      this.colorSwatchTargets.forEach(swatch => {
        this.markColorSwatch(swatch, swatch.dataset.colorValue === currentColor)
      })
    }

    if (this.hasIconInputTarget) {
      const currentIcon = this.iconInputTarget.value
      this.iconButtonTargets.forEach(btn => {
        this.markIconButton(btn, btn.dataset.iconValue === currentIcon)
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

  // selectColor: 色ボタンが押されたときに呼ばれる
  selectColor(event) {
    const button = event.currentTarget
    const color = button.dataset.colorValue

    // 送信用の hidden に選んだ色を入れる
    this.colorInputTarget.value = color

    // 押されたボタンだけを「選択中」、ほかはすべて「未選択」にする
    this.colorSwatchTargets.forEach(swatch => {
      this.markColorSwatch(swatch, swatch === button)
    })
  }

  // selectIcon: アイコンボタンが押されたときに呼ばれる
  selectIcon(event) {
    const button = event.currentTarget
    const icon = button.dataset.iconValue

    // 送信用の hidden に選んだアイコンを入れる
    this.iconInputTarget.value = icon

    // 押されたボタンだけを「選択中」、ほかはすべて「未選択」にする
    this.iconButtonTargets.forEach(btn => {
      this.markIconButton(btn, btn === button)
    })
  }

  // markColorSwatch: 色ボタン1つの「選択中／未選択」を、見た目と aria-pressed の両方に反映する
  //   selected: true なら選択中、false なら未選択
  //   String(selected): aria-pressed は文字列の "true" / "false" で指定するため変換する
  markColorSwatch(swatch, selected) {
    if (selected) {
      swatch.classList.add("ring-2", "ring-offset-2", "ring-gray-800", "scale-110")
    } else {
      swatch.classList.remove("ring-2", "ring-offset-2", "ring-gray-800", "scale-110")
    }
    swatch.setAttribute("aria-pressed", String(selected))
  }

  // markIconButton: アイコンボタン1つの「選択中／未選択」を、見た目と aria-pressed の両方に反映する
  markIconButton(btn, selected) {
    if (selected) {
      btn.classList.add("border-blue-500", "bg-blue-50", "scale-110")
      btn.classList.remove("border-gray-200")
    } else {
      btn.classList.remove("border-blue-500", "bg-blue-50", "scale-110")
      btn.classList.add("border-gray-200")
    }
    btn.setAttribute("aria-pressed", String(selected))
  }
}