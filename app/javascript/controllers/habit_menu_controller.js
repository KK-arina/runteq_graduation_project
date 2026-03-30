// app/javascript/controllers/habit_menu_controller.js
//
// ==============================================================================
// Stimulus コントローラー: 習慣カードの「⋯」メニュー + 削除確認モーダル（B-5 最終版）
// ==============================================================================
//
// 【設計方針】
//   モーダル・ボトムシートは content_for :modals で </body> 直前に出力する。
//   理由: 習慣カードの div に transition-shadow があり、fixed 要素の基準が
//         カード内になってしまうため、body直前に逃がすことで正しく全画面表示する。
//
// 【表示/非表示の制御方法】
//   Tailwind の hidden クラス（display: none !important）は
//   style.display = "flex" で上書きできない。
//   そのため初期状態を style="display: none" にして、
//   JS で style.display を直接操作する。
//
// 【イベントリスナーを openMenu() で設定する理由】
//   content_for :modals はページ末尾に出力されるため、
//   connect() 時点ではモーダルのDOMがまだ存在しない場合がある。
//   openMenu() が呼ばれた時点では必ずDOMが存在するため、そこで設定する。
//   _listenersAttached フラグで二重登録を防ぐ。
//
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  // ============================================================
  // static values
  // ============================================================
  //
  // habitName: 習慣名（モーダルタイトルに表示する）
  // modalId:   デスクトップ用モーダルのDOM ID（例: "habit-modal-1"）
  // sheetId:   スマホ用ボトムシートのDOM ID（例: "habit-sheet-1"）
  //
  static values = {
    habitName: String,
    modalId:   String,
    sheetId:   String
  }

  // ============================================================
  // connect()
  // ============================================================
  //
  // バインドした関数を保存する。
  // removeEventListener で同じ関数参照が必要なため connect() で作成しておく。
  // リスナーの登録は openMenu() で行う（DOMが存在するタイミングのため）。
  //
  connect() {
    this._boundCloseMenu    = this.closeMenu.bind(this)
    this._boundOverlayClick = this._handleOverlayClick.bind(this)
    this._listenersAttached = false
  }

  // ============================================================
  // disconnect()
  // ============================================================
  //
  // ページ遷移時にイベントリスナーを削除してメモリリークを防ぐ。
  // スクロール禁止も解除する。
  //
  disconnect() {
    document.body.style.overflow = ""

    if (!this._listenersAttached) return

    const habitId = this._habitId()

    const modal = this._getModal()
    if (modal) {
      modal.removeEventListener("click", this._boundOverlayClick)
      const panel = document.getElementById(`habit-modal-panel-${habitId}`)
      if (panel && this._stopModalPropagation) {
        panel.removeEventListener("click", this._stopModalPropagation)
      }
      const cancelBtn = document.getElementById(`habit-modal-cancel-${habitId}`)
      if (cancelBtn) cancelBtn.removeEventListener("click", this._boundCloseMenu)
    }

    const sheet = this._getSheet()
    if (sheet) {
      sheet.removeEventListener("click", this._boundOverlayClick)
      const panel = document.getElementById(`habit-sheet-panel-${habitId}`)
      if (panel && this._stopSheetPropagation) {
        panel.removeEventListener("click", this._stopSheetPropagation)
      }
      const cancelBtn = document.getElementById(`habit-sheet-cancel-${habitId}`)
      if (cancelBtn) cancelBtn.removeEventListener("click", this._boundCloseMenu)
    }
  }

  // ============================================================
  // openMenu()
  // ============================================================
  //
  // 「⋯」ボタンクリック時に呼ばれる。
  // ① 初回のみイベントリスナーを設定する
  // ② タイトルを更新する
  // ③ 背景スクロールを禁止する
  // ④ 画面幅に応じてモーダルかボトムシートを表示する
  //
  openMenu() {
    if (!this._listenersAttached) {
      this._setupModalListeners()
      this._setupSheetListeners()
      this._listenersAttached = true
    }

    this._updateModalTitle()
    document.body.style.overflow = "hidden"

    if (window.innerWidth >= 768) {
      this._openDesktopModal()
    } else {
      this._openBottomSheet()
    }
  }

  // ============================================================
  // closeMenu()
  // ============================================================
  closeMenu() {
    this._closeDesktopModal()
    this._closeBottomSheet()
    document.body.style.overflow = ""
  }

  // ============================================================
  // keydown(event)
  // ============================================================
  //
  // Escape キーでモーダルを閉じる（アクセシビリティ対応）。
  // data-action="keydown@window->habit-menu#keydown" から呼ばれる。
  //
  keydown(event) {
    if (event.key === "Escape") {
      this.closeMenu()
    }
  }

  // ============================================================
  // Private メソッド
  // ============================================================

  // ----------------------------------------------------------
  // _setupModalListeners()
  // ----------------------------------------------------------
  //
  // デスクトップ用モーダルにイベントリスナーを設定する。
  //
  // ① オーバーレイクリック → closeMenu()
  //    モーダル全体にリスナーを設定する。
  //
  // ② パネル内クリック → stopPropagation
  //    パネル内のクリックがオーバーレイまで伝播するのを防ぐ。
  //    伝播を止めないと、パネル内クリックでもモーダルが閉じてしまう。
  //
  // ③ キャンセルボタンクリック → closeMenu()
  //
  _setupModalListeners() {
    const modal = this._getModal()
    if (!modal) return

    const habitId = this._habitId()

    // ① オーバーレイクリックで閉じる
    modal.addEventListener("click", this._boundOverlayClick)

    // ② パネル内クリックの伝播をブロック
    const panel = document.getElementById(`habit-modal-panel-${habitId}`)
    if (panel) {
      this._stopModalPropagation = (e) => e.stopPropagation()
      panel.addEventListener("click", this._stopModalPropagation)
    }

    // ③ キャンセルボタンで閉じる
    const cancelBtn = document.getElementById(`habit-modal-cancel-${habitId}`)
    if (cancelBtn) {
      cancelBtn.addEventListener("click", this._boundCloseMenu)
    }
  }

  // ----------------------------------------------------------
  // _setupSheetListeners()
  // ----------------------------------------------------------
  _setupSheetListeners() {
    const sheet = this._getSheet()
    if (!sheet) return

    const habitId = this._habitId()

    sheet.addEventListener("click", this._boundOverlayClick)

    const panel = document.getElementById(`habit-sheet-panel-${habitId}`)
    if (panel) {
      this._stopSheetPropagation = (e) => e.stopPropagation()
      panel.addEventListener("click", this._stopSheetPropagation)
    }

    const cancelBtn = document.getElementById(`habit-sheet-cancel-${habitId}`)
    if (cancelBtn) {
      cancelBtn.addEventListener("click", this._boundCloseMenu)
    }
  }

  // ----------------------------------------------------------
  // _handleOverlayClick()
  // ----------------------------------------------------------
  //
  // stopPropagation でパネル内クリックはここに来ない。
  // このメソッドが呼ばれた = オーバーレイをクリックした。
  //
  _handleOverlayClick() {
    this.closeMenu()
  }

  // ----------------------------------------------------------
  // _updateModalTitle()
  // ----------------------------------------------------------
  _updateModalTitle() {
    const modal = this._getModal()
    const sheet = this._getSheet()

    if (modal) {
      const title = modal.querySelector(".js-habit-menu-title")
      if (title) title.textContent = `「${this.habitNameValue}」を削除しますか？`
    }

    if (sheet) {
      const title = sheet.querySelector(".js-habit-menu-title")
      if (title) title.textContent = `「${this.habitNameValue}」を削除しますか？`
    }
  }

  // ----------------------------------------------------------
  // _openDesktopModal() / _closeDesktopModal()
  // ----------------------------------------------------------
  //
  // 【display: none → flex の制御方法】
  //   Tailwind の hidden クラス（display: none !important）は
  //   style.display = "flex" で上書きできないため使用しない。
  //   初期状態を style="display: none" にして JS で直接操作する。
  //
  _openDesktopModal() {
    const modal = this._getModal()
    if (!modal) return
    modal.style.display = "flex"

    // モーダル内の最初のボタンにフォーカス（アクセシビリティ対応）
    setTimeout(() => {
      const firstButton = modal.querySelector("button")
      if (firstButton) firstButton.focus()
    }, 0)
  }

  _closeDesktopModal() {
    const modal = this._getModal()
    if (!modal) return
    modal.style.display = "none"
  }

  // ----------------------------------------------------------
  // _openBottomSheet() / _closeBottomSheet()
  // ----------------------------------------------------------
  //
  // translate-y-full → translate-y-0 のアニメーションでスライドインする。
  // setTimeout(10) でブラウザが初期状態を1フレーム描画してからアニメーション開始する。
  //
  _openBottomSheet() {
    const sheet = this._getSheet()
    if (!sheet) return

    const habitId = this._habitId()
    sheet.style.display = "flex"

    setTimeout(() => {
      const panel = document.getElementById(`habit-sheet-panel-${habitId}`)
      if (panel) {
        panel.classList.remove("translate-y-full")
        panel.classList.add("translate-y-0")
      }
    }, 10)
  }

  _closeBottomSheet() {
    const habitId = this._habitId()

    const panel = document.getElementById(`habit-sheet-panel-${habitId}`)
    if (panel) {
      panel.classList.remove("translate-y-0")
      panel.classList.add("translate-y-full")
    }

    setTimeout(() => {
      const sheet = this._getSheet()
      if (sheet) sheet.style.display = "none"
    }, 300)
  }

  // ----------------------------------------------------------
  // _getModal() / _getSheet() / _habitId()
  // ----------------------------------------------------------
  _getModal() {
    return document.getElementById(this.modalIdValue)
  }

  _getSheet() {
    return document.getElementById(this.sheetIdValue)
  }

  // "habit-modal-42" → "42" を抽出する
  _habitId() {
    return this.modalIdValue.replace("habit-modal-", "")
  }
}