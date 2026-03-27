// app/javascript/controllers/habit_record_controller.js
// =============================================================
// Stimulus コントローラー: 習慣記録の即時保存（B-1 レビュー修正版）
// =============================================================
//
// 【レビュー指摘による修正内容】
//
//   ① saveNumeric で event.target を使うように変更（最重要修正）
//      修正前: const input = this.numericInputTarget
//             → Stimulus の Target は「最初にマッチした1つ」だけを返す
//             → 複数の習慣が表示されている場合に、
//               他の習慣の input を誤って参照する可能性がある
//      修正後: async saveNumeric(event) { const input = event.target }
//             → event.target は「実際に変更された input」を返す
//             → 複数習慣が並んでいても正しい input に対して保存される
//
//   ② _setLoadingState に input 引数を追加
//      修正前: this.numericInputTarget.disabled = isLoading
//             → 全ての数値入力フィールドが一括でロックされる
//      修正後: _setLoadingState(isLoading, targetInput = null)
//             → 実際に操作している input のみロック
//             → 他の習慣の入力は影響を受けない
//
// 【なぜ event.target が正しいのか（重要な設計の理由）】
//   習慣が5件ある場合、data-controller="habit-record" を持つ要素が5つある。
//   各 Stimulus コントローラーのインスタンスは独立しているため、
//   「自分の要素配下の Target」しか認識しない。
//   正しく DOM 構造が組まれていれば this.numericInputTarget でも動くが、
//   event.target は「どの習慣の入力が変更されたか」を確実に把握できるため
//   より安全・明示的な実装になる。
// =============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ===========================================================
  // Targets の定義
  // ===========================================================
  static targets = [
    "checkbox",      // チェックボックス（チェック型習慣）
    "loading",       // ローディングスピナー（共通）
    "numericInput"   // 数値入力フィールド（数値型習慣）
  ]

  // ===========================================================
  // Values の定義
  // ===========================================================
  static values = {
    createUrl: String,  // POST URL
    updateUrl: String,  // PATCH URL
    recordId:  Number   // 0 = 未存在 / 1以上 = 既存レコード ID
  }

  // ===========================================================
  // toggle メソッド（チェック型専用）
  // ===========================================================
  async toggle() {
    const checkbox  = this.checkboxTarget
    const completed = checkbox.checked

    // チェックボックス単体をローディング状態にする
    // null を渡すことで「checkbox 以外のターゲットはロックしない」
    this._setLoadingState(true, null)

    try {
      const body = `completed=${completed ? "1" : "0"}`
      await this._sendRequest(body)
    } catch (error) {
      // 通信失敗 → チェックボックスを元の状態に戻す
      checkbox.checked = !completed
      console.error("チェック型保存エラー:", error)
    } finally {
      this._setLoadingState(false, null)
    }
  }

  // ===========================================================
  // saveNumeric メソッド（数値型専用・レビュー修正版）
  // ===========================================================
  // 【修正ポイント】
  //   引数に event を受け取り、event.target で「変更された input」を取得する。
  //   this.numericInputTarget は「このコントローラー配下の最初の numericInput」
  //   を返すが、event.target は「実際に操作された input 要素」を確実に返す。
  //
  // 【呼び出しタイミング】
  //   data-action="change->habit-record#saveNumeric" → フォーカスを外したとき
  async saveNumeric(event) {
    // event.target = 実際に変更された input 要素（確実に正しい要素を参照）
    const input = event.target
    const value = input.value.trim()

    // 空文字は「未入力のまま」なので送信しない
    if (value === "") return

    const numericValue = parseFloat(value)

    // 負の数や NaN は HTML 側の min="0" と二重チェック
    if (isNaN(numericValue) || numericValue < 0) {
      console.warn("無効な入力値:", value)
      input.value = ""
      return
    }

    // ── 修正: 操作している input だけをロックする ──────────────────────────
    // 第2引数に input を渡すことで「この input だけ disabled にする」
    // 他の習慣の入力フィールドは影響を受けない
    this._setLoadingState(true, input)
    // ────────────────────────────────────────────────────────────────────────

    try {
      const body = `numeric_value=${encodeURIComponent(numericValue)}`
      await this._sendRequest(body)

      // ── 成功時の視覚フィードバック（レビュー推奨の改善）──────────────────
      // 保存成功を示すために一瞬だけ緑色にフラッシュする。
      // CSS のクラス追加 → 800ms 後に削除という方法で実装する。
      // transition-colors が適用されている場合は滑らかにアニメーションする。
      input.classList.add("bg-green-50", "border-green-400")
      setTimeout(() => {
        input.classList.remove("bg-green-50", "border-green-400")
      }, 800)
      // ────────────────────────────────────────────────────────────────────────

    } catch (error) {
      console.error("数値型保存エラー:", error)
      // 数値型はエラー時に入力値をリセットしない（ユーザーが再編集できるようにする）
    } finally {
      this._setLoadingState(false, input)
    }
  }

  // ===========================================================
  // Private メソッド
  // ===========================================================

  // _sendRequest: HTTP リクエストを送信して Turbo Stream レスポンスを反映する
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

  // _setLoadingState（レビュー修正版）
  // 【修正ポイント】
  //   第2引数 targetInput を追加。
  //   数値型: 実際に操作している input だけをロックする（他の習慣に影響しない）
  //   チェック型: targetInput = null → checkbox のみロック
  //
  // 【引数】
  //   isLoading:   true = ロード開始 / false = ロード終了
  //   targetInput: 数値入力時に渡される input 要素（null の場合は無視）
  _setLoadingState(isLoading, targetInput = null) {
    // チェックボックスが存在する場合（チェック型）はチェックボックスをロック
    if (this.hasCheckboxTarget) {
      this.checkboxTarget.disabled = isLoading
    }

    // targetInput が指定された場合（数値型）はその input のみロック
    // ── 修正前: this.numericInputTarget.disabled（全 input をロック）
    // ── 修正後: targetInput のみロック（他の習慣の input は無影響）
    if (targetInput) {
      targetInput.disabled = isLoading
    }

    // ローディングスピナーの表示切り替え（共通）
    if (isLoading) {
      this.loadingTarget.removeAttribute("hidden")
    } else {
      this.loadingTarget.setAttribute("hidden", "")
    }
  }
}
