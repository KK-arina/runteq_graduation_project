// app/javascript/controllers/rest_mode_modal_controller.js
//
// ==============================================================================
// RestModeModalController（G-4 最終修正版）
// ==============================================================================
//
// 【根本原因と解決策】
//   content_for :modals でモーダルが </body> 直前に出力されるため、
//   モーダル内の要素（ボタン等）は data-controller スコープの外に出る。
//
//   ❌ 機能しない方法:
//     モーダル内ボタンに data-action="click->rest-mode-modal#submitForm"
//     → Stimulus がスコープ外なので認識しない
//
//   ✅ 解決策（B-5 / C-3 と同じ方式）:
//     openModal() の中で addEventListener を直接登録する。
//     _listenersAttached フラグで二重登録を防ぐ。
//
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  // ============================================================
  // static targets
  // ============================================================
  //
  // フォーム内の要素のみ target として宣言する。
  // これらはフォーム（data-controller 要素）の子孫なので target で取得できる。
  // モーダル内の要素は content_for :modals で外に出るため target を使わない。
  static targets = [
    "untilDate",  // 日付入力フィールド（フォーム内）
    "reason"      // 理由入力フィールド（フォーム内）
  ]

  // ============================================================
  // connect()
  // ============================================================
  //
  // コントローラーが DOM に接続されたとき自動で呼ばれる。
  connect() {
    // ESC キーでモーダルを閉じるリスナーを登録する
    this._escapeHandler = (event) => {
      if (event.key === "Escape") this.closeModal()
    }
    window.addEventListener("keydown", this._escapeHandler)

    // race condition 対策: タイマー ID の初期化
    this._closeTimer = null

    // モーダル内ボタンへのリスナー未登録フラグ
    // （openModal() で初回のみ登録する）
    this._listenersAttached = false

    // 各メソッドの this を固定する（removeEventListener のために保持する）
    this._boundSubmitForm      = this.submitForm.bind(this)
    this._boundCloseModal      = this.closeModal.bind(this)
    this._boundCloseFromOverlay = this.closeFromOverlay.bind(this)
  }

  // ============================================================
  // disconnect()
  // ============================================================
  //
  // コントローラーが DOM から切り離されたとき自動で呼ばれる。
  // メモリリーク防止のためリスナーをすべて削除する。
  disconnect() {
    window.removeEventListener("keydown", this._escapeHandler)
    if (this._closeTimer) clearTimeout(this._closeTimer)
    document.body.classList.remove("overflow-hidden")

    // モーダル内ボタンのリスナーも削除する
    this._removeModalListeners()
  }

  // ============================================================
  // openModal()
  // ============================================================
  //
  // 「お休みモードを開始する」ボタンがクリックされたとき呼ばれる。
  // このボタンはフォーム内にあるので data-action で呼べる。
  openModal() {
    // ① 日付が未入力ならブラウザ標準バリデーションを表示して処理を止める
    if (this.hasUntilDateTarget && !this.untilDateTarget.value) {
      this.untilDateTarget.reportValidity()
      return
    }

    // ② フォームの入力値を確認表示に反映する
    this._updateConfirmDisplay()

    // ③ 背景スクロールを禁止する
    document.body.classList.add("overflow-hidden")

    // ④ overlay を表示する
    //    content_for :modals で body 直前に出力されるため
    //    document.getElementById() で直接取得する
    const overlay = document.getElementById("rest-mode-modal")
    if (overlay) {
      overlay.style.display = "flex"
    }

    // ⑤ 初回のみモーダル内ボタンにリスナーを登録する
    //    （B-5 / C-3 の _listenersAttached パターンと同じ）
    if (!this._listenersAttached) {
      this._setupModalListeners()
      this._listenersAttached = true
    }

    // ⑥ 画面幅に応じてデスクトップかボトムシートかを切り替える
    if (window.innerWidth >= 768) {
      this._openDesktopModal()
    } else {
      this._openBottomSheet()
    }
  }

  // ============================================================
  // closeModal()
  // ============================================================
  //
  // モーダルを閉じる。
  // ESC キー・モーダル内キャンセルボタン・× ボタンから呼ばれる。
  closeModal() {
    if (this._closeTimer) {
      clearTimeout(this._closeTimer)
      this._closeTimer = null
    }

    this._closeBottomSheet()

    // アニメーション完了後（300ms）に overlay を非表示にする
    this._closeTimer = setTimeout(() => {
      const overlay = document.getElementById("rest-mode-modal")
      if (overlay) overlay.style.display = "none"
      document.body.classList.remove("overflow-hidden")
      this._closeTimer = null
    }, 300)
  }

  // ============================================================
  // closeFromOverlay()
  // ============================================================
  //
  // オーバーレイ（半透明背景）クリックでモーダルを閉じる。
  // addEventListener で半透明背景 div に登録する。
  closeFromOverlay() {
    this.closeModal()
  }

  // ============================================================
  // submitForm()
  // ============================================================
  //
  // 「開始する」ボタンがクリックされたとき呼ばれる。
  // addEventListener で登録されるため、data-action は不要。
  submitForm() {
    const form = document.getElementById("rest-mode-form")
    if (form) {
      // requestSubmit() を使う理由:
      //   form.submit() は submit イベントを発火しないため Turbo が介入できない。
      //   requestSubmit() は通常のフォーム送信と同じく submit イベントを発火し、
      //   Turbo が正しく処理できる。また CSRF トークンも正常に送信される。
      form.requestSubmit()
    }
    this.closeModal()
  }

  // ============================================================
  // Private メソッド
  // ============================================================

  // ----------------------------------------------------------
  // _setupModalListeners()
  // ----------------------------------------------------------
  //
  // モーダル内のボタンに addEventListener を登録する。
  // content_for :modals でスコープ外に出た要素は
  // data-action では動作しないため、ここで直接登録する。
  //
  // 【B-5 / C-3 との違い】
  //   B-5 は習慣ごとに異なる ID を持つモーダルを使う。
  //   G-4 はページ全体で1つのモーダルだけなので
  //   固定の ID で取得できる。
  _setupModalListeners() {
    // ── デスクトップ用モーダルのリスナー ──────────────────────────────

    // 「開始する」ボタン
    const submitBtn = document.getElementById("rest-mode-submit-btn")
    if (submitBtn) {
      submitBtn.addEventListener("click", this._boundSubmitForm)
    }

    // 「キャンセル」ボタン（× ボタンと同じメソッド）
    const cancelBtn = document.getElementById("rest-mode-cancel-btn")
    if (cancelBtn) {
      cancelBtn.addEventListener("click", this._boundCloseModal)
    }

    // × 閉じるボタン
    const closeBtn = document.getElementById("rest-mode-close-btn")
    if (closeBtn) {
      closeBtn.addEventListener("click", this._boundCloseModal)
    }

    // オーバーレイ（半透明背景）クリックで閉じる
    const overlay = document.getElementById("rest-mode-modal")
    if (overlay) {
      overlay.addEventListener("click", this._boundCloseFromOverlay)
    }

    // ── スマホ用ボトムシートのリスナー ────────────────────────────────

    // 「開始する」ボタン（スマホ用）
    const submitBtnMobile = document.getElementById("rest-mode-submit-btn-mobile")
    if (submitBtnMobile) {
      submitBtnMobile.addEventListener("click", this._boundSubmitForm)
    }

    // 「キャンセル」ボタン（スマホ用）
    const cancelBtnMobile = document.getElementById("rest-mode-cancel-btn-mobile")
    if (cancelBtnMobile) {
      cancelBtnMobile.addEventListener("click", this._boundCloseModal)
    }
  }

  // ----------------------------------------------------------
  // _removeModalListeners()
  // ----------------------------------------------------------
  //
  // disconnect() 時にリスナーを削除してメモリリークを防ぐ。
  _removeModalListeners() {
    if (!this._listenersAttached) return

    const submitBtn = document.getElementById("rest-mode-submit-btn")
    if (submitBtn) submitBtn.removeEventListener("click", this._boundSubmitForm)

    const cancelBtn = document.getElementById("rest-mode-cancel-btn")
    if (cancelBtn) cancelBtn.removeEventListener("click", this._boundCloseModal)

    const closeBtn = document.getElementById("rest-mode-close-btn")
    if (closeBtn) closeBtn.removeEventListener("click", this._boundCloseModal)

    const overlay = document.getElementById("rest-mode-modal")
    if (overlay) overlay.removeEventListener("click", this._boundCloseFromOverlay)

    const submitBtnMobile = document.getElementById("rest-mode-submit-btn-mobile")
    if (submitBtnMobile) submitBtnMobile.removeEventListener("click", this._boundSubmitForm)

    const cancelBtnMobile = document.getElementById("rest-mode-cancel-btn-mobile")
    if (cancelBtnMobile) cancelBtnMobile.removeEventListener("click", this._boundCloseModal)
  }

  // ----------------------------------------------------------
  // _updateConfirmDisplay()
  // ----------------------------------------------------------
  _updateConfirmDisplay() {
    const untilDateValue = this.hasUntilDateTarget
      ? this.untilDateTarget.value
      : ""

    let formattedDate = "未設定"
    if (untilDateValue) {
      const parts = untilDateValue.split("-")
      if (parts.length === 3) {
        const year  = parseInt(parts[0], 10)
        const month = parseInt(parts[1], 10)
        const day   = parseInt(parts[2], 10)
        formattedDate = `${year}年${month}月${day}日`
      }
    }

    const reasonValue = this.hasReasonTarget
      ? this.reasonTarget.value.trim()
      : ""

    const confirmUntilDate = document.getElementById("confirm-until-date")
    if (confirmUntilDate) confirmUntilDate.textContent = formattedDate

    const confirmUntilDateMobile = document.getElementById("confirm-until-date-mobile")
    if (confirmUntilDateMobile) confirmUntilDateMobile.textContent = formattedDate

    const confirmReason = document.getElementById("confirm-reason")
    if (confirmReason) {
      confirmReason.textContent = reasonValue ? `理由: ${reasonValue}` : ""
    }

    const confirmReasonMobile = document.getElementById("confirm-reason-mobile")
    if (confirmReasonMobile) {
      confirmReasonMobile.textContent = reasonValue ? `理由: ${reasonValue}` : ""
    }
  }

  // ----------------------------------------------------------
  // _openDesktopModal()
  // ----------------------------------------------------------
  _openDesktopModal() {
    setTimeout(() => {
      const panel = document.getElementById("rest-mode-modal-panel")
      if (panel) {
        const firstFocusable = panel.querySelector(
          'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
        )
        if (firstFocusable) firstFocusable.focus()
      }
    }, 0)
  }

  // ----------------------------------------------------------
  // _openBottomSheet() / _closeBottomSheet()
  // ----------------------------------------------------------
  _openBottomSheet() {
    const panel = document.getElementById("rest-mode-sheet-panel")
    if (!panel) return

    setTimeout(() => {
      panel.classList.remove("translate-y-full")
      panel.classList.add("translate-y-0")
    }, 10)
  }

  _closeBottomSheet() {
    const panel = document.getElementById("rest-mode-sheet-panel")
    if (!panel) return

    panel.classList.remove("translate-y-0")
    panel.classList.add("translate-y-full")
  }
}