// app/javascript/controllers/flash_controller.js
//
// ============================================================
// 【このファイルの役割】
// フラッシュメッセージを「トースト通知」として動作させる Stimulus コントローラー。
// ① 一定時間後に自動で消える（フェードアウト付き）
// ② ✕ボタンで手動でも閉じられる
//
// 【Issue #27 での変更点】
// dismiss() にフェードアウトアニメーションを追加。
// hidden クラスを付けるだけでなく、まず opacity を 0 にして
// 0.5秒のアニメーション後に hidden で非表示にする。
// これで「本物のトースト」らしい滑らかな消え方になる。
// ============================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // static targets:
  //   HTML 側で data-flash-target="message" と書いた要素を
  //   JavaScript 側で this.messageTarget として参照できるようにする。
  static targets = ["message"]

  // static values:
  //   HTML 側で data-flash-duration-value="5000" と書いた値を
  //   JavaScript 側で this.durationValue として参照できるようにする。
  //   type: Number → 数値として扱う
  //   default: 4000 → 指定がない場合は 4秒
  static values = { duration: { type: Number, default: 4000 } }

  // connect():
  //   Stimulus のライフサイクルメソッド。
  //   このコントローラーが接続された（HTMLに追加された）ときに自動で呼ばれる。
  connect() {
    // setTimeout:
    //   指定したミリ秒後に関数を実行する JavaScript の組み込み関数。
    //   this.durationValue ミリ秒後に dismiss() を呼び出す。
    //   bind(this) は「setTimeout のコールバック内でも this が
    //   コントローラーを指し続ける」ようにするため。
    this.timer = setTimeout(this.dismiss.bind(this), this.durationValue)
  }

  // disconnect():
  //   このコントローラーが切断された（HTMLから削除された）ときに自動で呼ばれる。
  //   タイマーをクリアしてメモリリーク（不要な処理が残ること）を防ぐ。
  disconnect() {
    if (this.timer) {
      clearTimeout(this.timer)
    }
  }

  // dismiss():
  //   フラッシュメッセージをフェードアウトして消すメソッド。
  //   ✕ボタンの data-action="flash#dismiss" から呼ばれる。
  //   setTimeout のコールバックからも呼ばれる。
  dismiss() {
    // hasMessageTarget:
    //   messageTarget が存在するかどうかを確認する。
    //   存在しない状態でアクセスするとエラーになるため、必ずチェックする。
    if (this.hasMessageTarget) {
      // ① CSS transition でフェードアウトアニメーションを設定する。
      //   style.transition: opacity が 0.5秒かけて変化するよう設定する。
      //   ease: アニメーションの速度変化を「最初と最後は遅め、途中は速め」にする自然な動き。
      this.messageTarget.style.transition = "opacity 0.5s ease"

      // ② opacity を 0 にしてフェードアウト開始。
      //   opacity: 0 は完全透明。ただしまだ display は残っているので
      //   レイアウト上のスペースはそのまま（他の要素が動かない）。
      this.messageTarget.style.opacity = "0"

      // ③ 0.5秒後（フェードアウト完了後）に hidden クラスを追加して完全非表示にする。
      //   hidden は Tailwind の display: none に相当する。
      //   500ms は ① の transition 時間と合わせる（0.5秒 = 500ms）。
      setTimeout(() => {
        // アニメーション終了後にターゲットがまだ存在するか再確認する。
        // 0.5秒の間にページ遷移などで要素が消えた場合のエラー防止。
        if (this.hasMessageTarget) {
          this.messageTarget.classList.add("hidden")
        }
      }, 500)
    }
  }
}