// app/javascript/controllers/form_submit_controller.js
//
// ============================================================
// 【このファイルの役割】
//   フォームの送信ボタンに「送信中...」のローディング状態を表示する
//   Stimulus コントローラー。
//
// 【なぜこのコントローラーが必要か】
//   local: true のフォームは通常のHTMLフォーム送信（フルページリロード）を行う。
//   送信ボタンを押してからサーバーの応答が返るまでの間、
//   ユーザーには「何も起きていない」ように見えてしまう。
//   これを防ぐため、送信直後にボタンを「送信中...」に変化させ、
//   二重送信も防止する。
//
// 【動作の仕組み】
//   1. フォームの submit イベントを検知する
//   2. ボタンのテキストを「送信中...」に変える
//   3. ボタンを disabled にして二重送信を防ぐ
//   4. スピナーアイコンを表示する
//
// 【使い方（HTML側）】
//   <form data-controller="form-submit"
//         data-action="submit->form-submit#submit">
//     <button data-form-submit-target="button"
//             data-loading-text="送信中...">
//       送信する
//     </button>
//   </form>
// ============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // static targets:
  //   HTML 側で data-form-submit-target="button" と書いた要素を
  //   JavaScript 側で this.buttonTarget として参照できるようにする。
  //   ここでは送信ボタンが対象。
  static targets = ["button"]

  // ============================================================
  // connect()
  // ============================================================
  // Stimulus のライフサイクルメソッド。
  // このコントローラーが DOM に接続されたとき（ページ読み込み時）に
  // 自動的に呼ばれる。
  //
  // 【なぜ connect() でボタンを初期化するのか】
  //   「ブラウザの戻るボタン」でこのページに戻ったとき、
  //   ブラウザによっては直前のDOM状態（disabled になったボタン）を
  //   キャッシュして復元することがある。
  //   そのままだとボタンが永遠に押せない状態になってしまうため、
  //   ページが表示されるたびに connect() で disabled を解除して初期化する。
  //
  // 【具体的な問題シナリオ】
  //   1. フォームを送信 → ボタンが disabled になる
  //   2. ブラウザの戻るボタンを押してフォームページに戻る
  //   3. connect() がなければ disabled のままボタンが表示される → 操作不能
  //   4. connect() があれば → 自動で有効状態に戻る
  connect() {
    if (this.hasButtonTarget) {
      // disabled を false に戻す（有効化）
      this.buttonTarget.disabled = false
      // 見た目のクラスも除去して、通常のボタンスタイルに戻す
      this.buttonTarget.classList.remove("opacity-70", "cursor-not-allowed")
    }
  }

  // ============================================================
  // submit()
  // ============================================================
  // フォームの submit イベントが発生したとき（ボタンがクリックされたとき）に
  // 呼び出されるメソッド。
  // data-action="submit->form-submit#submit" から呼び出される。
  submit() {
    // hasButtonTarget:
    //   buttonTarget が存在するかどうかを確認するプロパティ。
    //   Stimulus が自動生成する。ターゲットが見つからない場合のエラーを防ぐ。
    if (!this.hasButtonTarget) return

    const button = this.buttonTarget

    // data-loading-text 属性:
    //   HTML 側でボタンに data-loading-text="送信中..." と指定しておくことで、
    //   送信中の表示テキストをビュー側から柔軟に変更できる。
    //   指定がなければ「送信中...」をデフォルト値として使う。
    const loadingText = button.dataset.loadingText || "送信中..."

    // ボタンのテキストをローディング表示に変更する。
    // innerHTML を使うことで、テキストの前にスピナーSVGを追加できる。
    //
    // animate-spin: Tailwind CSS のクラス。要素を無限に回転させる。
    // aria-hidden="true": 装飾用SVGのためスクリーンリーダーに読み上げさせない。
    button.innerHTML = `
      <svg class="animate-spin -ml-1 mr-2 h-4 w-4 text-white inline-block"
           xmlns="http://www.w3.org/2000/svg"
           fill="none"
           viewBox="0 0 24 24"
           aria-hidden="true">
        <circle class="opacity-25"
                cx="12" cy="12" r="10"
                stroke="currentColor"
                stroke-width="4"></circle>
        <path class="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z">
        </path>
      </svg>
      ${loadingText}
    `

    // disabled = true:
    //   ボタンを無効化する。
    //   ① ユーザーが連打しても2回目以降のフォーム送信が発生しない（二重送信防止）
    //   ② ボタンが操作できないことを視覚的に示す（opacity が自動で下がる）
    button.disabled = true

    // opacity-70: 透明度を下げて「押せない状態」を視覚的に強調する
    // cursor-not-allowed: マウスカーソルを禁止マーク（🚫）に変えて操作不能を示す
    button.classList.add("opacity-70", "cursor-not-allowed")
  }
}