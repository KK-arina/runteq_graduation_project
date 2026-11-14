// app/javascript/controllers/ai_limit_modal_controller.js
//
// ==============================================================================
// AiLimitModalController（D-6）
// ==============================================================================
//
// 【アクセシビリティ修正での変更】
//   submitWithoutAi で、押されたボタンが入っているフォームを使うようにした。
//   以前は this.submitFormTarget（同じ名前のターゲットのうち最初の1つ＝パソコン用）を
//   使っていたため、スマホでボタンを押しても、隠れているパソコン用のフォームに値を
//   コピーして送信していた。結果は同じだったが、押したボタンと送信するフォームを
//   一致させておくほうが分かりやすく、今後どちらかのフォームだけ変更しても壊れない。
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "desktopModal",
    "mobileSheet",
    "submitForm"   // complete_without_ai 専用フォーム（パソコン用とスマホ用の2つ）
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
  //   1. 押されたボタンが入っているフォーム（complete_without_ai 専用）を特定する
  //   2. ページ内のメインフォーム（振り返り入力フォーム）の各値を
  //      そのフォームの hidden フィールドにコピーする
  //   3. そのフォームを送信する
  //
  // 【なぜメインフォームを書き換えないのか】
  //   render :new で描画されたページでは form の action が
  //   相対パスや絶対パスで不安定になる場合があるため、
  //   独立した専用フォームを使う方が確実。
  submitWithoutAi(event) {
    event.preventDefault()

    // ── 送信するフォームを特定する（アクセシビリティ修正で変更）──────────────
    // event.currentTarget.closest("form"):
    //   押されたボタンから外側へたどり、いちばん近い form を取得する。
    //   スマホで押せばスマホ用、パソコンで押せばパソコン用のフォームになる。
    // || this.submitFormTarget:
    //   万一 form が見つからない場合は、以前と同じく最初のフォームを使う（安全策）。
    const form = event.currentTarget.closest("form") || this.submitFormTarget

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

      // 送信するフォームの中の hidden フィールドを取得する
      const targetField = form.querySelector(
        `input[data-field="${fieldName}"]`
      )

      if (sourceField && targetField) {
        // メインフォームの値を hidden フィールドにコピーする
        targetField.value = sourceField.value
      }
    })
    // ────────────────────────────────────────────────────────────────────────

    // complete_without_ai 専用フォームを送信する
    form.submit()
  }

  closeOnOverlay(event) {
    if (event.target === event.currentTarget) {
      this.close()
    }
  }
}