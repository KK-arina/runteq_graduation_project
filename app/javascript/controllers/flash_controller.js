// ファイルパス: app/javascript/controllers/flash_controller.js
//
// 【このファイルの役割】
// フラッシュメッセージを一定時間後に自動で消す Stimulus コントローラー。
// また、✕ボタンで手動でも閉じられるようにする。
//
// 【Stimulus とは？】
// Hotwire の一部。HTML の data 属性と JavaScript を結びつける軽量なフレームワーク。
// jQuery のような複雑な DOM 操作なしに、シンプルに JS の動作を追加できる。
//
// 【このコントローラーの動作】
// 1. connect() でコントローラーが起動したとき、data-flash-duration-value ミリ秒後に自動で消す
// 2. dismiss() で ✕ボタンを押したとき即座に消す

import { Controller } from "@hotwired/stimulus"

// export default class で このコントローラーを他から呼べるようにする
export default class extends Controller {
  // static targets
  //   → HTML 側で data-flash-target="message" と書いた要素を
  //     JavaScript 側で this.messageTarget として参照できるようにする
  static targets = ["message"]

  // static values
  //   → HTML 側で data-flash-duration-value="5000" と書いた値を
  //     JavaScript 側で this.durationValue として参照できるようにする
  //   → type: Number は数値型として扱う
  //   → default: 4000 は指定がない場合のデフォルト値（4秒）
  static values = { duration: { type: Number, default: 4000 } }

  // connect()
  //   → Stimulus のライフサイクルメソッド
  //   → このコントローラーが接続された（HTML に追加された）ときに自動で呼ばれる
  connect() {
    // setTimeout
    //   → 指定したミリ秒後に関数を実行する JavaScript の組み込み関数
    //   → this.durationValue ミリ秒後に this.dismiss を呼ぶ
    //   → bind(this) は「this が setTimeout のコールバック内でも正しく参照される」ようにするため
    this.timer = setTimeout(this.dismiss.bind(this), this.durationValue)
  }

  // disconnect()
  //   → このコントローラーが切断された（HTML から削除された）ときに自動で呼ばれる
  //   → タイマーをクリアして、不要な処理が走らないようにする（メモリリーク防止）
  disconnect() {
    if (this.timer) {
      clearTimeout(this.timer)
    }
  }

  // dismiss()
  //   → フラッシュメッセージを消すメソッド
  //   → ✕ボタンの data-action="flash#dismiss" から呼ばれる
  //   → setTimeout のコールバックからも呼ばれる
  dismiss() {
    // hasMessageTarget
    //   → messageTarget が存在するかどうかを確認する
    //   → 存在しない場合に messageTarget にアクセスするとエラーになるため
    if (this.hasMessageTarget) {
      // classList.add("hidden")
      //   → Tailwind の hidden クラスを追加して要素を非表示にする
      //   → display: none と同じ効果
      //
      // remove() で要素ごと削除することもできるが、
      // hidden にすることでアクセシビリティ（スクリーンリーダー）でも対応できる
      this.messageTarget.classList.add("hidden")
    }
  }
}
