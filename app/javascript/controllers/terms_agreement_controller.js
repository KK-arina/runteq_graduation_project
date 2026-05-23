// app/javascript/controllers/terms_agreement_controller.js
//
// ==============================================================================
// F-3: 利用規約・プライバシーポリシー同意チェックボックス制御コントローラー
// ==============================================================================
//
// 【このコントローラーの役割】
//   登録フォームの「利用規約に同意する」チェックボックスの
//   ON/OFF に応じて、送信ボタンの活性/非活性を切り替える。
//
// 【なぜ Stimulus を使うのか】
//   - インライン script だと Turbo のページ遷移で
//     イベントリスナーが重複登録されるバグが発生する。
//   - Stimulus は connect()/disconnect() でライフサイクルを自動管理するため
//     Turbo と相性が良く、メモリリークも防げる。
//
// 【HTML 側の使い方（data 属性の対応）】
//   <form data-controller="terms-agreement">
//     <input type="checkbox"
//            data-terms-agreement-target="checkbox"
//            data-action="change->terms-agreement#toggle">
//     <button data-terms-agreement-target="button" disabled>登録する</button>
//   </form>
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ============================================================
  // static targets（ターゲット定義）
  // ============================================================
  //
  // Stimulus の「ターゲット」は、このコントローラーが JS から
  // 直接操作する DOM 要素に名前をつける仕組み。
  //
  // 定義すると Stimulus が自動的に以下のプロパティを生成してくれる:
  //   this.checkboxTarget → data-terms-agreement-target="checkbox" の要素
  //   this.buttonTarget   → data-terms-agreement-target="button" の要素
  static targets = ["checkbox", "button"]

  // ============================================================
  // connect()
  // ============================================================
  //
  // 【役割】
  //   コントローラーが DOM に接続されたとき（ページ表示時）に
  //   自動的に呼ばれる Stimulus のライフサイクルメソッド。
  //   ページ読み込み直後・Turbo のキャッシュ復元時にも呼ばれるため、
  //   初期状態のボタン活性/非活性を正しく設定するために使う。
  connect() {
    this.toggle()
  }

  // ============================================================
  // toggle()
  // ============================================================
  //
  // 【役割】
  //   チェックボックスの ON/OFF に合わせてボタンの活性/非活性と
  //   見た目（Tailwind クラス）を切り替える。
  //   data-action="change->terms-agreement#toggle" によって
  //   チェックボックスの状態変化時に自動的に呼ばれる。
  //
  // 【disabled プロパティについて】
  //   disabled = true  → ボタンがクリックできない（非活性・フォーム送信されない）
  //   disabled = false → ボタンがクリックできる（活性）
  //
  // 【! （否定演算子）について】
  //   チェックあり (checked=true)  → !true  = false → disabled=false → 活性
  //   チェックなし (checked=false) → !false = true  → disabled=true  → 非活性
  toggle() {
    // チェックボックスが ON かどうかを真偽値で取得する
    const isChecked = this.checkboxTarget.checked

    // ボタンの送信可否（disabled プロパティ）を切り替える
    this.buttonTarget.disabled = !isChecked

    // Tailwind CSS クラスを動的に切り替えてボタンの見た目を変える
    //
    // classList.toggle("クラス名", 条件):
    //   条件が true  → そのクラスを要素に追加する
    //   条件が false → そのクラスを要素から削除する
    //
    // チェックあり → bg-blue-600（青・活性）の見た目にする
    // チェックなし → bg-gray-400（グレー・非活性）の見た目にする
    this.buttonTarget.classList.toggle("bg-blue-600",       isChecked)
    this.buttonTarget.classList.toggle("hover:bg-blue-700", isChecked)
    this.buttonTarget.classList.toggle("bg-gray-400",       !isChecked)
    this.buttonTarget.classList.toggle("cursor-not-allowed", !isChecked)
  }
}