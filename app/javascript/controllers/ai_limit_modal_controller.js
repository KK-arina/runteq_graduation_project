// app/javascript/controllers/ai_limit_modal_controller.js
//
// ==============================================================================
// AiLimitModalController（D-6）
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "desktopModal",
    "mobileSheet",
    "submitForm"   // complete_without_ai 専用フォーム
  ]

  static values = {
    show: Boolean
  }

  connect() {
    if (this.showValue) {
      this.open()
    }
  }

  open() {
    document.body.style.overflow = "hidden"
    if (window.innerWidth >= 768) {
      this.desktopModalTarget.style.display = "flex"
    } else {
      this.mobileSheetTarget.style.display = "flex"
    }
  }

  close() {
    document.body.style.overflow = ""
    this.desktopModalTarget.style.display = "none"
    this.mobileSheetTarget.style.display  = "none"
  }

  // ============================================================
  // submitWithoutAi(event)
  // ============================================================
  //
  // 【処理の流れ】
  //   1. ページ内のメインフォーム（振り返り入力フォーム）を取得する
  //   2. メインフォームの各フィールドの値を
  //      モーダル内の hidden フィールドにコピーする
  //   3. モーダル内の complete_without_ai 専用フォームを送信する
  //
  // 【なぜメインフォームを書き換えないのか】
  //   render :new で描画されたページでは form の action が
  //   相対パスや絶対パスで不安定になる場合があるため、
  //   独立した専用フォームを使う方が確実。
  submitWithoutAi(event) {
    event.preventDefault()

    // ── メインフォームから入力値を取得する ──────────────────────────────
    // data-field 属性でフィールドを特定する（IDやnameの変動に対応）
    const fields = [
      "reflection_comment",
      "direct_reason",
      "background_situation",
      "next_action"
    ]

    fields.forEach(fieldName => {
      // メインフォームのフィールドを取得する
      // name="weekly_reflection[field_name]" の形式で検索する
      const sourceField = document.querySelector(
        `textarea[name="weekly_reflection[${fieldName}]"],
         input[name="weekly_reflection[${fieldName}]"]`
      )

      // モーダル内の hidden フィールドを取得する
      const targetField = this.submitFormTarget.querySelector(
        `input[data-field="${fieldName}"]`
      )

      if (sourceField && targetField) {
        // メインフォームの値を hidden フィールドにコピーする
        targetField.value = sourceField.value
      }
    })
    // ────────────────────────────────────────────────────────────────────────

    // complete_without_ai 専用フォームを送信する
    this.submitFormTarget.submit()
  }

  closeOnOverlay(event) {
    if (event.target === event.currentTarget) {
      this.close()
    }
  }
}