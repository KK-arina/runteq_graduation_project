// app/javascript/controllers/notification_limit_controller.js
//
// ==============================================================================
// NotificationLimitController（G-3 新規作成）
// ==============================================================================
//
// 【このコントローラーの役割】
//   通知設定ページの「1日の最大通知数」スライダーをドラッグしたとき、
//   隣の「N件」というテキストをリアルタイムで書き換える。
//
// 【なぜ Stimulus を使うのか（inline script を使わない理由）】
//   inline script（<script>タグ）を使うと Turbo ページ遷移時に
//   イベントリスナーが多重登録されてメモリリークが起きる。
//   Stimulus の connect()/disconnect() でライフサイクルが自動管理されるため
//   Turbo と相性が良くクリーンな実装になる。
//
// 【HTML 側での使い方】
//   <div data-controller="notification-limit">
//     <input type="range"
//            data-notification-limit-target="slider"
//            data-action="input->notification-limit#update">
//     <span data-notification-limit-target="display">5件</span>
//   </div>
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ============================================================
  // static targets: このコントローラーが参照する HTML 要素の宣言
  // ============================================================
  //
  // 宣言すると Stimulus が自動的に以下を生成する:
  //   this.sliderTarget  → data-notification-limit-target="slider" の要素
  //   this.displayTarget → data-notification-limit-target="display" の要素
  //   this.hasSliderTarget  → slider ターゲットが存在するか（boolean）
  //   this.hasDisplayTarget → display ターゲットが存在するか（boolean）
  static targets = ["slider", "display"]

  // ============================================================
  // connect(): コントローラーが DOM に接続されたとき自動で呼ばれる
  // ============================================================
  //
  // 【なぜ connect() で update() を呼ぶのか】
  //   ページ読み込み時・Turbo キャッシュ復元時に
  //   スライダーの初期値を display に反映するため。
  //   これがないとページ表示時に display の「N件」と
  //   スライダーの実際の位置がずれる場合がある。
  connect() {
    this.update()
  }

  // ============================================================
  // update(): スライダーの値が変わったとき呼ばれる
  // ============================================================
  //
  // 【呼ばれるタイミング】
  //   data-action="input->notification-limit#update" により
  //   スライダー（range input）の input イベントで呼ばれる。
  //   input イベントはドラッグ中リアルタイムで発火する
  //   （change はドラッグを離した瞬間のみ発火）。
  update() {
    // ターゲット要素が存在しない場合は何もしない（安全策）。
    // 存在しない要素にアクセスするとエラーが発生するため必ずチェックする。
    if (!this.hasSliderTarget || !this.hasDisplayTarget) return

    // スライダーの現在値を取得する。
    // input 要素の .value は常に文字列型（例: "5"）で返るが
    // テキスト表示にそのまま使えるため parseInt は不要。
    const value = this.sliderTarget.value

    // 「N件」形式で表示テキストを更新する。
    // テンプレートリテラル（バックティック + ${}）で文字列を組み立てる。
    this.displayTarget.textContent = `${value}件`
  }
}