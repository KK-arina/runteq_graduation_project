// app/javascript/controllers/mobile_menu_controller.js
// =============================================================
// 【このファイルの役割】
//   モバイル用ハンバーガーメニューの開閉を制御する Stimulus コントローラー。
//   _header.html.erb の data-controller="mobile-menu" から呼び出される。
//
// 【Stimulus の基本的な仕組み】
//   Controller : JS処理のクラス（このファイル）
//   Target     : JSから操作したいHTML要素（data-mobile-menu-target="xxx"）
//   Action     : イベントとメソッドの紐付け（data-action="click->mobile-menu#toggle"）
//
// 【このコントローラーが担う処理】
//   1. ハンバーガーボタンのクリックでメニューを開閉する
//   2. メニュー外クリックでメニューを閉じる
//   3. ESCキーでメニューを閉じる（キーボード操作・アクセシビリティ対応）
//   4. メニューが開いている間は背景スクロールを無効化する
//   5. ARIA属性を更新してスクリーンリーダーに状態を伝える
// =============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

  // ---- Targets の定義 ----
  // HTML側の data-mobile-menu-target="xxx" に対応する要素を
  // this.menuTarget / this.buttonTarget などで参照できるようにする。
  //
  // menu      : ドロップダウンメニュー全体（開閉対象）
  // button    : ハンバーガーボタン（aria-expanded を動的に更新する）
  // openIcon  : 三本線アイコン（メニューが閉じているときに表示）
  // closeIcon : ×アイコン（メニューが開いているときに表示）
  static targets = ["menu", "button", "openIcon", "closeIcon"]

  // ---- connect() ----
  // Stimulus がコントローラーを DOM に接続したときに自動的に呼ばれる。
  // イベントリスナーの登録など、初期化処理をここで行う。
  connect() {
    // isOpen: メニューが現在開いているかを管理する内部フラグ
    this.isOpen = false

    // bind(this) を使う理由：
    //   通常の関数をイベントリスナーに渡すと、関数内の this が
    //   コントローラーではなくイベントのターゲット要素になってしまう。
    //   bind(this) でこのコントローラーのインスタンスに固定する。
    //   また、disconnect() で removeEventListener するには
    //   addEventListener に渡したのと「全く同じ関数参照」が必要なので
    //   プロパティとして保持しておく必要がある。
    this.handleOutsideClick = this.closeOnOutsideClick.bind(this)
    this.handleEscape = this.closeOnEscape.bind(this)

    // ESCキーのリスナーはページ読み込み時から常時登録する。
    // メニューが閉じているときに押されても isOpen チェックで何もしないので問題ない。
    document.addEventListener("keydown", this.handleEscape)
  }

  // ---- disconnect() ----
  // コントローラーが DOM から切り離されたときに自動的に呼ばれる。
  // connect() で追加したイベントリスナーをすべて解除する。
  //
  // 【重要】解除し忘れると「メモリリーク」が発生する。
  //   コントローラーが破棄された後もイベントリスナーがメモリに残り続け、
  //   不要な処理が走り続けてしまう。Turbo でページ遷移を繰り返すと
  //   特に顕著になるため、必ず disconnect() で解除する。
  disconnect() {
    document.removeEventListener("click", this.handleOutsideClick)
    document.removeEventListener("keydown", this.handleEscape)
    // コントローラー破棄時にスクロールロックが残らないよう念のため解除する
    document.body.classList.remove("overflow-hidden")
  }

  // ---- toggle() ----
  // ハンバーガーボタンのクリック時に呼ばれる（data-action="click->mobile-menu#toggle"）。
  // 現在の開閉状態を反転させる。
  toggle() {
    this.isOpen = !this.isOpen
    if (this.isOpen) {
      this._openMenu()
    } else {
      this._closeMenu()
    }
  }

  // ---- closeOnOutsideClick() ----
  // メニューが開いている状態でヘッダー外をクリックしたら閉じる。
  //
  // this.element：
  //   data-controller="mobile-menu" が付いている要素（<header>）を指す。
  // this.element.contains(event.target)：
  //   クリックされた要素が <header> の子孫かどうかを確認する。
  //   true  → ヘッダー内クリック → 何もしない
  //   false → ヘッダー外クリック → メニューを閉じる
  closeOnOutsideClick(event) {
    if (this.isOpen && !this.element.contains(event.target)) {
      this.isOpen = false
      this._closeMenu()
    }
  }

  // ---- closeOnEscape() ----
  // ESCキーが押されたときにメニューを閉じる。
  // キーボード操作・スクリーンリーダー利用者のためのアクセシビリティ対応。
  closeOnEscape(event) {
    if (event.key === "Escape" && this.isOpen) {
      this.isOpen = false
      this._closeMenu()
    }
  }

  // ============================================================
  // プライベートメソッド（_ で始まる名前は「クラス内部専用」という慣習）
  // ============================================================

  // ---- _openMenu() ----
  // メニューを「開く」ときの DOM 操作をすべてここに集約する。
  _openMenu() {
    // ① メニューを表示する
    //    hidden クラスを削除 → display:none が解除されて要素が現れる
    this.menuTarget.classList.remove("hidden")

    // ② 三本線アイコンを非表示にする
    this.openIconTarget.classList.add("hidden")

    // ③ ×アイコンを表示する
    this.closeIconTarget.classList.remove("hidden")

    // ④ aria-expanded を "true" に更新する
    //    スクリーンリーダーに「メニューが開いた」ことを伝える
    this.buttonTarget.setAttribute("aria-expanded", "true")

    // ⑤ 背景スクロールを無効化する
    //    overflow-hidden は overflow: hidden; を適用する Tailwind クラス。
    //    body に追加するとページ全体のスクロールが止まる。
    //    モーダルやドロワーメニューで一般的なUXテクニック。
    document.body.classList.add("overflow-hidden")

    // ⑥ メニュー外クリックの検知を開始する
    //    二重登録を防ぐため remove してから add する
    document.removeEventListener("click", this.handleOutsideClick)
    document.addEventListener("click", this.handleOutsideClick)
  }

  // ---- _closeMenu() ----
  // メニューを「閉じる」ときの DOM 操作をすべてここに集約する。
  _closeMenu() {
    // ① メニューを非表示にする
    //    hidden クラスを追加 → display:none が適用されて要素が消える
    this.menuTarget.classList.add("hidden")

    // ② ×アイコンを非表示にする
    this.closeIconTarget.classList.add("hidden")

    // ③ 三本線アイコンを表示する
    this.openIconTarget.classList.remove("hidden")

    // ④ aria-expanded を "false" に更新する
    this.buttonTarget.setAttribute("aria-expanded", "false")

    // ⑤ 背景スクロールを再び有効にする
    document.body.classList.remove("overflow-hidden")

    // ⑥ メニュー外クリックの検知を解除する
    document.removeEventListener("click", this.handleOutsideClick)
  }
}