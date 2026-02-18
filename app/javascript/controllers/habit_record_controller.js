// ==============================================================================
// habit_record_controller.js（Issue #15 修正版）
// ==============================================================================
// 【修正内容】
//   if (window.Turbo) { Turbo.renderStreamMessage(...) }
//   　↓ window.Turbo に統一
//   if (window.Turbo) { window.Turbo.renderStreamMessage(...) }
//
// 【なぜ window.Turbo に統一するか】
//   JavaScript のスコープ問題を防ぐため。
//   import { Turbo } from "@hotwired/turbo" でインポートした Turbo と
//   window.Turbo（グローバル変数）は同じオブジェクトだが、
//   バンドラーの設定によっては別オブジェクトになる可能性がある。
//   window.Turbo に統一することで「グローバルの Turbo を使う」と明示できる。
//   また、Turbo がロードされているかの確認（if window.Turbo）と
//   呼び出し（window.Turbo.renderStreamMessage）を同じ参照にすることで
//   より安全で一貫性のあるコードになる。
// ==============================================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "loading"]
  static values  = {
    createUrl: String,
    updateUrl: String,
    recordId:  Number
  }

  connect() {
    this._timeoutId = null
    console.log("[HabitRecord] コントローラー接続:", this.element)
  }

  toggle(event) {
    const checked = event.target.checked
    this._setLoadingState(true)

    if (this._timeoutId) clearTimeout(this._timeoutId)

    // タイムアウト処理（10秒でエラー）
    this._timeoutId = setTimeout(() => {
      console.error("[HabitRecord] タイムアウト")
      this._setLoadingState(false)
      event.target.checked = !checked
      this._showTemporaryError("タイムアウトしました。再度お試しください。")
    }, 10000)

    this._sendRequest(checked, event.target)
  }

  async _sendRequest(checked, checkboxElement) {
    // CSRF トークンを meta タグから取得する
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    const isNewRecord = this.recordIdValue === 0
    const url         = isNewRecord ? this.createUrlValue : this.updateUrlValue
    const method      = isNewRecord ? "POST" : "PATCH"

    const formData = new FormData()
    formData.append("completed", checked ? "1" : "0")

    try {
      const response = await fetch(url, {
        method,
        headers: {
          "X-CSRF-Token": csrfToken,
          "Accept":       "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"
        },
        body: formData
      })

      if (!response.ok) {
        throw new Error(`HTTP Error: ${response.status} ${response.statusText}`)
      }

      const responseText = await response.text()

      // ==============================================================
      // 【修正箇所】window.Turbo に統一する
      // ==============================================================
      // 修正前: if (window.Turbo) { Turbo.renderStreamMessage(responseText) }
      //   → if の条件では window.Turbo を確認しているのに、
      //     呼び出しは import された Turbo を使っている（不一致）
      //
      // 修正後: if (window.Turbo) { window.Turbo.renderStreamMessage(responseText) }
      //   → 確認も呼び出しも window.Turbo に統一（一貫性・安全性が向上）
      // ==============================================================
      if (window.Turbo) {
        window.Turbo.renderStreamMessage(responseText)
      }

      // タイムアウトタイマーをクリア
      if (this._timeoutId) {
        clearTimeout(this._timeoutId)
        this._timeoutId = null
      }

      this._setLoadingState(false)
      console.log("[HabitRecord] 保存成功:", { checked, url, method })

    } catch (error) {
      console.error("[HabitRecord] 保存失敗:", error)

      if (this._timeoutId) {
        clearTimeout(this._timeoutId)
        this._timeoutId = null
      }

      this._setLoadingState(false)

      // 楽観的 UI の取り消し: チェックを元に戻す
      checkboxElement.checked = !checked
      this._showTemporaryError("保存に失敗しました。再度お試しください。")
    }
  }

  _setLoadingState(isLoading) {
    if (this.hasCheckboxTarget) {
      this.checkboxTarget.disabled = isLoading
    }
    if (this.hasLoadingTarget) {
      this.loadingTarget.hidden = !isLoading
    }
  }

  _showTemporaryError(message) {
    let errorEl = document.getElementById("habit_record_error_toast")

    if (!errorEl) {
      errorEl                = document.createElement("div")
      errorEl.id             = "habit_record_error_toast"
      errorEl.className      = [
        "fixed", "bottom-4", "right-4", "z-50",
        "bg-red-100", "border", "border-red-400", "text-red-700",
        "px-4", "py-3", "rounded", "shadow-lg",
        "transition-opacity", "duration-300"
      ].join(" ")
      document.body.appendChild(errorEl)
    }

    errorEl.textContent    = message
    errorEl.hidden         = false
    errorEl.style.opacity  = "1"

    setTimeout(() => {
      errorEl.style.opacity = "0"
      setTimeout(() => {
        if (errorEl.parentNode) errorEl.parentNode.removeChild(errorEl)
      }, 300)
    }, 3000)
  }

  disconnect() {
    if (this._timeoutId) clearTimeout(this._timeoutId)
  }
}