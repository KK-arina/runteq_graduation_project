// app/javascript/controllers/habit_record_controller.js
// =============================================================
// Stimulus コントローラー: 習慣記録の即時保存（B-7 最終修正版）
// =============================================================
//
// 【修正内容】
//
//   ① 「変更項目だけ送る」設計に変更（最重要修正）
//
//      【修正前の問題】
//        toggle() と saveNumeric() がメモの値も一緒に送っていた。
//        これにより「チェックした瞬間に古いメモで上書き」が起きるリスクがあった。
//
//        例:
//          ユーザーがメモを入力中（未保存）
//          → チェックボックスを操作
//          → 入力途中のメモが誤って保存される
//
//      【修正後の設計】
//        toggle()     → completed だけ送る
//        saveNumeric() → numeric_value だけ送る
//        saveMemo()   → memo だけ送る
//
//        各操作は「自分の項目だけ」を更新する責務を持つ。
//        Service 側が NOT_PROVIDED で区別するため、送らなかった項目はDBが変わらない。
//
// =============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ===========================================================
  // Targets の定義
  // ===========================================================
  static targets = [
    "checkbox",     // チェックボックス（チェック型習慣）
    "loading",      // ローディングスピナー（共通）
    "numericInput", // 数値入力フィールド（数値型習慣）
    "memoArea",     // メモ入力エリア全体（hidden クラスを切り替える）
    "memoToggle",   // 💬 ボタン（アイコン色を変更する）
    "memoTextarea", // メモのテキストエリア（入力値の取得・書き換え）
    "memoCount"     // 文字数カウンター（xx/200 の表示）
  ]

  // ===========================================================
  // Values の定義
  // ===========================================================
  static values = {
    createUrl: String,
    updateUrl: String,
    recordId:  Number
  }

  // ===========================================================
  // connect() ライフサイクルフック
  // ===========================================================
  connect() {
    if (this.hasMemoTextareaTarget) {
      this._originalMemo = this.memoTextareaTarget.value
    }
  }

  // ===========================================================
  // toggle メソッド（チェック型専用）
  // ===========================================================
  //
  // 【修正内容】
  //   メモを一緒に送るのをやめた。
  //   completed だけを送ることで「チェック操作がメモを変更しない」を保証する。
  //
  // 【なぜ completed だけでよいのか】
  //   Service 側が NOT_PROVIDED を使って「送られなかった項目は更新しない」
  //   という部分更新設計になったため、memo を省略しても既存のメモは消えない。
  async toggle() {
    const checkbox  = this.checkboxTarget
    const completed = checkbox.checked

    this._setLoadingState(true, null)

    try {
      // completed だけを送る（memo は送らない = DB の memo は変わらない）
      const body = `completed=${completed ? "1" : "0"}`
      await this._sendRequest(body)
    } catch (error) {
      checkbox.checked = !completed
      console.error("チェック型保存エラー:", error)
    } finally {
      this._setLoadingState(false, null)
    }
  }

  // ===========================================================
  // saveNumeric メソッド（数値型専用）
  // ===========================================================
  //
  // 【修正内容】
  //   メモを一緒に送るのをやめた。
  //   numeric_value だけを送ることで「数値操作がメモを変更しない」を保証する。
  async saveNumeric(event) {
    const input = event.target
    const value = input.value.trim()

    if (value === "") return

    const numericValue = parseFloat(value)

    if (isNaN(numericValue) || numericValue < 0) {
      console.warn("無効な入力値:", value)
      input.value = ""
      return
    }

    this._setLoadingState(true, input)

    try {
      // numeric_value だけを送る（memo は送らない = DB の memo は変わらない）
      const body = `numeric_value=${encodeURIComponent(numericValue)}`
      await this._sendRequest(body)

      input.classList.add("bg-green-50", "border-green-400")
      setTimeout(() => {
        input.classList.remove("bg-green-50", "border-green-400")
      }, 800)

    } catch (error) {
      console.error("数値型保存エラー:", error)
    } finally {
      this._setLoadingState(false, input)
    }
  }

  // ===========================================================
  // toggleMemo メソッド（B-7 追加）
  // ===========================================================
  toggleMemo() {
    const area = this.memoAreaTarget
    area.classList.toggle("hidden")

    if (!area.classList.contains("hidden")) {
      this.memoTextareaTarget.focus()
    }
  }

// app/javascript/controllers/habit_record_controller.js
// saveMemo メソッドのみ以下に差し替える

  // ===========================================================
  // saveMemo メソッド（B-7 追加）
  // ===========================================================
  //
  // 【設計の核心】
  //   memo だけを送る。completed も numeric_value も送らない。
  //   Service 側が NOT_PROVIDED で区別するため、memo だけが更新される。
  //
  // 【Turbo Stream 差し替え後の問題と解決策】
  //   _sendRequest 内で window.Turbo.renderStreamMessage が実行されると
  //   この data-controller="habit-record" 要素全体が新しい HTML に差し替えられる。
  //   差し替え後は this.memoAreaTarget や this.loadingTarget への参照が無効になる。
  //
  //   解決策:
  //     ① _setLoadingState を呼ばない（loadingTarget への参照を避ける）
  //     ② try/finally ではなく try/catch のみにする
  //     ③ DOM差し替え後に古い要素を操作しない
  async saveMemo() {
    const memoValue = this.memoTextareaTarget.value

    if (memoValue.length > 200) {
      alert("メモは200文字以内で入力してください")
      return
    }

    // 保存前にメモエリアを閉じる
    // 【なぜ保存前に閉じるのか】
    //   Turbo Stream の差し替え前に hidden にしておかないと、
    //   差し替え後のレンダリングでエリアの開閉状態が崩れる場合がある。
    //   メモが存在する場合は show_memo_area = true なので
    //   サーバーから返ってくる HTML では展開状態で描画される。
    this.memoAreaTarget.classList.add("hidden")

    try {
      // memo だけを送る
      // completed も numeric_value も送らないことで
      // 「メモ保存がチェック状態や数値を変更しない」を保証する
      const body = `memo=${encodeURIComponent(memoValue)}`

      // _sendRequest の中で Turbo.renderStreamMessage が実行され
      // この要素（data-controller="habit-record"）全体が差し替えられる。
      // 差し替え後は this への参照が無効になるため、
      // await の後に this.xxx を呼んではいけない。
      await this._sendRequest(body)

      // ここに到達した時点でDOMは差し替え済み。
      // this.memoToggleTarget や this.loadingTarget は存在しない。
      // 何もしない（UIの更新はサーバーから返ったHTMLが担う）。

    } catch (error) {
      // エラー時のみメモエリアを再度開く
      // エラーの場合は Turbo Stream が差し替えを実行しないため
      // this.memoAreaTarget はまだ有効な要素を指している
      if (this.hasMemoAreaTarget) {
        this.memoAreaTarget.classList.remove("hidden")
      }
      console.error("メモ保存エラー:", error)
      alert("メモの保存に失敗しました。もう一度お試しください。")
    }

    // 【finally を削除した理由】
    //   finally ブロックで this._setLoadingState(false, null) を呼ぶと
    //   this.loadingTarget にアクセスするが、
    //   Turbo Stream の差し替え後はこの要素が存在しないためエラーになる。
    //   loading の非表示はサーバーから返ってくる HTML（hidden 属性付き）が担う。
  }

  // ===========================================================
  // cancelMemo メソッド（B-7 追加）
  // ===========================================================
  cancelMemo() {
    if (this.hasMemoTextareaTarget) {
      this.memoTextareaTarget.value = this._originalMemo || ""
      this._updateMemoCount(this._originalMemo || "")
    }
    this.memoAreaTarget.classList.add("hidden")
  }

  // ===========================================================
  // updateMemoCount メソッド（B-7 追加）
  // ===========================================================
  updateMemoCount(event) {
    const text = event.target.value
    this._updateMemoCount(text)
  }

  // ===========================================================
  // Private メソッド
  // ===========================================================

  async _sendRequest(body) {
    const url    = this.recordIdValue === 0 ? this.createUrlValue : this.updateUrlValue
    const method = this.recordIdValue === 0 ? "POST" : "PATCH"

    const response = await Promise.race([
      fetch(url, {
        method,
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content,
          "Accept":       "text/vnd.turbo-stream.html",
          "Content-Type": "application/x-www-form-urlencoded"
        },
        body
      }),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error("タイムアウト")), 8000)
      )
    ])

    if (!response.ok) throw new Error(`HTTP ${response.status}`)

    const responseText = await response.text()
    window.Turbo.renderStreamMessage(responseText)
  }

  _setLoadingState(isLoading, targetInput = null) {
    if (this.hasCheckboxTarget) {
      this.checkboxTarget.disabled = isLoading
    }
    if (targetInput) {
      targetInput.disabled = isLoading
    }
    if (isLoading) {
      this.loadingTarget.removeAttribute("hidden")
    } else {
      this.loadingTarget.setAttribute("hidden", "")
    }
  }

// app/javascript/controllers/habit_record_controller.js
// _updateMemoCount メソッドのみ修正する

  // _updateMemoCount
  // 【役割】
  //   文字数カウンター（data-habit-record-target="memoCount"）を更新する。
  //   200文字を超えたら保存ボタンを無効化する。
  _updateMemoCount(text) {
    if (!this.hasMemoCountTarget) return

    const count = text.length
    this.memoCountTarget.textContent = `${count}/200`

    // 180文字以上で警告色（赤）にする
    if (count >= 180) {
      this.memoCountTarget.classList.add("text-red-500")
      this.memoCountTarget.classList.remove("text-gray-400")
    } else {
      this.memoCountTarget.classList.add("text-gray-400")
      this.memoCountTarget.classList.remove("text-red-500")
    }

    // ── 追加: 200文字超で保存ボタンを無効化 ────────────────────────────────
    //
    // 【なぜ保存ボタンを無効化するのか】
    //   日本語入力（IME）では maxlength が変換確定前には効かない。
    //   200文字を超えている状態で保存しようとすると
    //   サーバーのバリデーションエラーになるため、
    //   クライアント側でも事前に保存できないようにする。
    //
    // 【querySelectorAll を使う理由】
    //   data-action="click->habit-record#saveMemo" を持つボタンを探す。
    //   Stimulus の Target ではないため querySelector で直接取得する。
    //   memoArea の中にある保存ボタンだけを対象にするため
    //   this.memoAreaTarget.querySelector で絞り込む。
    if (this.hasMemoAreaTarget) {
      const saveButton = this.memoAreaTarget.querySelector('[data-action*="saveMemo"]')
      if (saveButton) {
        if (count > 200) {
          saveButton.disabled = true
          saveButton.classList.add("opacity-50", "cursor-not-allowed")
          saveButton.classList.remove("hover:bg-blue-600")
        } else {
          saveButton.disabled = false
          saveButton.classList.remove("opacity-50", "cursor-not-allowed")
          saveButton.classList.add("hover:bg-blue-600")
        }
      }
    }
    // ────────────────────────────────────────────────────────────────────────
  }

  _updateMemoToggleStyle(hasMemo) {
    if (!this.hasMemoToggleTarget) return

    if (hasMemo) {
      this.memoToggleTarget.classList.add("text-blue-500")
      this.memoToggleTarget.classList.remove("text-gray-400")
    } else {
      this.memoToggleTarget.classList.add("text-gray-400")
      this.memoToggleTarget.classList.remove("text-blue-500")
    }
  }
}