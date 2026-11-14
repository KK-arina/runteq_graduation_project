// app/javascript/controllers/remember_me_controller.js
//
// ==============================================================================
// RememberMeController（ログイン画面の「ログインしたままにする」連携）
// ==============================================================================
//
// 【このコントローラーの役割】
//   ログイン画面の「ログインしたままにする」チェックボックスの状態を、
//   Google / LINE ログインボタンのフォームにも反映する。
//
// 【なぜ必要なのか】
//   Google / LINE ボタンは、メールログインとは別の <form> になっている。
//   HTML のチェックボックスは1つのフォームにしか所属できないため、
//   そのままでは Google / LINE でログインしたときにチェック状態が伝わらない。
//
// 【なぜ hidden 項目ではなく URL のクエリ（?remember_me=1）にするのか】
//   OmniAuth（リリース版 2.1 系）は、認証開始時の「URL のクエリ」だけを
//   セッションに保存し、Google / LINE から戻ってきたコールバックで
//   request.env["omniauth.params"] として渡してくれる。
//   フォームの hidden 項目（POST の本文）は引き継がれないため、URL に付ける。
//   既存の LINE 通知連携が ?origin=notification を使っているのと同じ考え方。
//
// 【JavaScript が無効なときの動き】
//   URL に remember_me が付かないため、ログイン保持は行われない（安全側に倒れる）。
//
// 【ファイル名と data-controller の対応】
//   remember_me_controller.js → data-controller="remember-me"
//   （Stimulus はファイル名のアンダースコアをハイフンに変えた名前で登録する）
// ==============================================================================
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // static targets: HTML 側の data-remember-me-target="..." と対応する
  //   checkbox  : 「ログインしたままにする」チェックボックス（1つ）
  //   oauthForm : Google / LINE ボタンのフォーム（環境変数の設定により0〜2個）
  static targets = ["checkbox", "oauthForm"]

  // connect(): この要素が画面に表示されたときに自動で呼ばれる
  //   パスワード間違いで画面が再表示され、チェックが付いた状態で始まる場合にも
  //   最初から URL を正しい状態にしておくため、ここでも sync() を呼ぶ。
  connect() {
    this.sync()
  }

  // sync(): チェック状態を Google / LINE フォームの送信先 URL に反映する
  //   チェックの切り替え（change イベント）のたびに呼ばれる。
  sync() {
    // チェックボックスがない画面（新規登録ページなど）では何もしない
    if (!this.hasCheckboxTarget) return

    // チェックあり → "1"、なし → "0"
    //   "0" を明示的に送る理由: サーバー側で「保持しない」と確実に判断できるようにするため。
    //   （値がない場合は「設定画面からの連携」とみなし、保持状態を変えない設計にしている）
    const value = this.checkboxTarget.checked ? "1" : "0"

    this.oauthFormTargets.forEach((form) => {
      // new URL(相対パス, 基準URL): "/auth/google_oauth2" を扱いやすい URL オブジェクトにする
      //   getAttribute("action") を使う理由: form.action だと
      //   ブラウザが絶対 URL に変換した値になるため、元の属性値から組み立てる。
      const url = new URL(form.getAttribute("action"), window.location.origin)

      // searchParams.set: remember_me があれば上書き、なければ追加する
      //   何度チェックを切り替えても ?remember_me=1&remember_me=0 のように重複しない。
      url.searchParams.set("remember_me", value)

      // 同じサイト内の送信先なので、パスとクエリだけを action に戻す
      form.setAttribute("action", url.pathname + url.search)
    })
  }
}