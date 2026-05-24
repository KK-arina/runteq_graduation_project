// app/javascript/controllers/deactivate_modal_controller.js
//
// ==============================================================================
// DeactivateModalController: 退会確認モーダルを制御する Stimulus コントローラー
// ==============================================================================
//
// 【このコントローラーの役割】
//   退会確認モーダル（M-4）の表示・非表示を制御する。
//   HTML の data-controller="deactivate-modal" が付いた要素に自動で紐付く。
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // open: モーダルを表示する
  // data-action="click->deactivate-modal#open" の要素がクリックされたとき呼ばれる
  open() {
    // hidden クラスを外すことで表示する（Tailwind の hidden = display: none）
    this.element.classList.remove("hidden")
    // モーダル表示中は背景スクロールを禁止する（UX改善）
    document.body.classList.add("overflow-hidden")
  }

  // close: モーダルを非表示にする
  // ×ボタン・キャンセルボタン・オーバーレイクリックで呼ばれる
  close() {
    this.element.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  // disconnect: Stimulus がコントローラーを切り離すときに呼ばれる
  // Turbo でページ遷移したとき overflow-hidden が残るバグを防ぐ
  disconnect() {
    document.body.classList.remove("overflow-hidden")
  }
}