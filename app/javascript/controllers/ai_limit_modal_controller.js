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
//
// 【AI分析状態の修正での変更】
//   気分スコア（mood）もコピーするようにした。
//   気分スコアの入力欄はラジオボタン（星評価など）の場合もあるため、
//   値の読み取りを #readMainFormValue にまとめ、どちらの形でも読めるようにした。
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

    // ── コピーする項目の一覧 ──────────────────────────────────────────────
    // mood（気分スコア）は AI分析状態の修正で追加した。
    const fields = [
      "reflection_comment",
      "direct_reason",
      "background_situation",
      "next_action",
      "mood"
    ]

    fields.forEach(fieldName => {
      // メインフォームの値を読み取る（見つからなければ null）
      const value = this.#readMainFormValue(fieldName)

      // 送信するフォームの中の hidden フィールドを取得する
      const targetField = form.querySelector(
        `input[data-field="${fieldName}"]`
      )

      if (value !== null && targetField) {
        // メインフォームの値を hidden フィールドにコピーする
        targetField.value = value
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

  // ============================================================
  // #readMainFormValue(fieldName)（AI分析状態の修正で追加）
  // ============================================================
  //
  // 【役割】
  //   メインフォームの name="weekly_reflection[項目名]" の値を読み取る。
  //
  // 【ラジオボタンを特別扱いする理由】
  //   ラジオボタンは同じ name の input が複数並び、選ばれている1つ（:checked）の
  //   値だけが送信される。最初の input の値をそのまま読むと、選んでいない値を
  //   コピーしてしまうため、checked のものを探す。何も選ばれていなければ空文字。
  //
  // 【戻り値】
  //   値の文字列。該当する入力欄がページに無い場合は null。
  #readMainFormValue(fieldName) {
    const name = `weekly_reflection[${fieldName}]`
    const elements = Array.from(document.querySelectorAll(`[name="${name}"]`))

    if (elements.length === 0) return null

    const radios = elements.filter(element => element.type === "radio")
    if (radios.length > 0) {
      const checked = radios.find(radio => radio.checked)
      return checked ? checked.value : ""
    }

    // textarea / hidden input / text input など: 最後の要素の値を使う
    // （Rails はチェックボックスの前に hidden を置くため、後ろの要素が実際の入力欄になる）
    return elements[elements.length - 1].value
  }
}