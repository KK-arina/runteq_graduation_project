// app/javascript/controllers/alarm_toggle_controller.js
//
// ==============================================================================
// AlarmToggleController - アラームチェックボックスの ON/OFF 制御
// ==============================================================================
//
// 【このコントローラーの役割】
//   alarm_enabled チェックボックスの状態に応じて
//   alarm_minutes_before の入力欄を有効/無効に切り替える。
//
//   チェックOFF → 入力欄を disabled にして視覚的に薄く表示する
//   チェックON  → 入力欄を enabled にして通常表示に戻す
//
// 【Stimulus の基本構造】
//   data-controller="alarm-toggle" → この JS ファイルが読み込まれる
//   data-alarm-toggle-target="checkbox" → チェックボックス要素を参照
//   data-alarm-toggle-target="minutesInput" → 分数入力欄を参照
//   data-action="change->alarm-toggle#toggle" → change イベントで toggle() を呼ぶ
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ターゲット定義
  // 【static targets とは】
  //   Stimulus が自動的に this.checkboxTarget と this.minutesInputTarget
  //   というプロパティを生成してくれる。
  //   data-alarm-toggle-target="checkbox" の要素を自動で取得する。
  static targets = ["checkbox", "minutesInput"]

  // connect()
  // 【役割】
  //   コントローラーが DOM に接続されたとき（ページ読み込み時）に自動実行される。
  //   初期状態のチェックボックスの値に応じて入力欄の状態を設定する。
  connect() {
    this.toggle()
  }

  // toggle()
  // 【役割】
  //   チェックボックスの状態を見て minutesInput の有効/無効を切り替える。
  //   data-action="change->alarm-toggle#toggle" で呼び出される。
  toggle() {
    const isEnabled = this.checkboxTarget.checked

    if (isEnabled) {
      // チェックON: 入力欄を有効にして通常表示にする
      this.minutesInputTarget.disabled = false
      this.minutesInputTarget.classList.remove("opacity-40", "cursor-not-allowed", "bg-gray-100")
    } else {
      // チェックOFF: 入力欄を無効にして薄く表示する
      // 【disabled の効果】
      //   フォーム送信時に disabled な input の値は送信されない。
      //   そのため alarm_minutes_before が送信されなくなる。
      //   Rails 側で alarm_minutes_before が nil になっても
      //   to_i で 0 に変換されるため問題ない。
      this.minutesInputTarget.disabled = true
      this.minutesInputTarget.classList.add("opacity-40", "cursor-not-allowed", "bg-gray-100")
    }
  }
}
