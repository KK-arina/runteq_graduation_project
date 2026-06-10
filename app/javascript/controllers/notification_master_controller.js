// app/javascript/controllers/notification_master_controller.js
//
// ==============================================================================
// NotificationMasterController（G-3 修正: 通知全般マスタースイッチの連動を追加）
// ==============================================================================
//
// 【このコントローラーの役割】
//   通知全般（マスタースイッチ）のON/OFFに連動して、
//   通知チャネル（LINE・メール・週次レポート）の操作可否を切り替える。
//
// 【仕様】
//   マスタースイッチOFF時:
//     - チャネルセクションをグレーアウト（opacity-50）する
//     - pointer-events-none でクリック不可にする
//     - チャネルの設定値は変更しない（値を保持したまま見た目だけ変える）
//   マスタースイッチON時:
//     - グレーアウトを解除して操作可能に戻す
//
// 【なぜ disabled を使わないのか】
//   disabled にするとフォーム送信時に値が送られなくなり、
//   チャネルの設定が false に上書きされてしまう。
//   opacity-50 + pointer-events-none で視覚的・操作的に無効化するだけにする。
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["master", "channel"]

  // ============================================================
  // connect(): コントローラーが DOM に接続されたとき自動で呼ばれる
  // ============================================================
  // ページ読み込み時にマスタースイッチの状態を反映する。
  connect() {
    this.applyMasterState()
  }

  // ============================================================
  // toggle(): マスタースイッチが変更されたとき呼ばれる
  // ============================================================
  // data-action="change->notification-master#toggle" で発火する。
  toggle() {
    this.applyMasterState()
  }

  // ============================================================
  // applyMasterState(): マスタースイッチの状態をチャネルに反映する
  // ============================================================
  applyMasterState() {
    if (!this.hasMasterTarget) return

    const enabled = this.masterTarget.checked

    this.channelTargets.forEach(channel => {
      if (enabled) {
        // マスターON: チャネルの操作制限を解除する
        channel.classList.remove("opacity-50", "pointer-events-none")
      } else {
        // マスターOFF: チャネルをグレーアウトして操作不可にする
        channel.classList.add("opacity-50", "pointer-events-none")
      }
    })
  }
}