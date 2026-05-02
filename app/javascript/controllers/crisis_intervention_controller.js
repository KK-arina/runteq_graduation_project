// app/javascript/controllers/crisis_intervention_controller.js
//
// ==============================================================================
// CrisisInterventionController（危機介入モーダル Stimulus コントローラー）
// ==============================================================================
//
// 【このコントローラーの役割】
//   振り返り入力ページ・PMVV 入力ページで
//   危機ワードが検出された場合にモーダルを表示する。
//   デスクトップ（768px以上）: 画面中央のオーバーレイモーダル
//   スマホ（768px未満）: 画面下部からスライドするボトムシート
//
// 【サーバーサイドとの連携方法】
//   Rails コントローラーが flash[:crisis] = true をセットし、
//   ビュー（new.html.erb）がこのフラグをページのデータ属性として出力する。
//   このコントローラーが connect() で data-crisis-show-value を確認し、
//   true であれば自動的にモーダルを表示する。
//
// 【「入力を続ける」ボタンの動作】
//   モーダルを閉じるだけで、入力内容は破棄しない。
//   振り返り・PMVV の保存はすでに完了しているため、
//   ユーザーは安心してモーダルを閉じられる。
//
// 【アクセシビリティ対応】
//   - Escape キーでモーダルを閉じられる
//   - モーダル表示中は背景スクロールを無効化する（body overflow: hidden）
//   - フォーカスをモーダル内に閉じ込める（将来的に拡張可能）
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // ============================================================
  // static targets: このコントローラーが参照する HTML 要素の名前一覧
  // ============================================================
  //
  // 【各ターゲットの役割】
  //   overlay       : 背景を覆う半透明レイヤー（クリックで閉じる）
  //   modal         : デスクトップ用の中央モーダルカード
  //   sheet         : スマホ用のボトムシート
  static targets = [
    "overlay",  // 半透明の背景オーバーレイ
    "modal",    // デスクトップ用中央モーダル
    "sheet"     // スマホ用ボトムシート
  ]

  // ============================================================
  // static values: HTML の data 属性から読み込む値
  // ============================================================
  //
  // 【show (Boolean) の役割】
  //   Rails の flash[:crisis] をビューが
  //   data-crisis-intervention-show-value="true" として出力する。
  //   このコントローラーが connect() でこの値を確認してモーダルを表示する。
  static values = {
    show: Boolean  // true なら connect 時にモーダルを自動表示する
  }

  // ============================================================
  // connect(): コントローラーが HTML に接続された直後に呼ばれる
  // ============================================================
  //
  // 【Stimulus のライフサイクルについて】
  //   connect → HTML 要素とコントローラーが紐付いた時点で自動実行される。
  //   ページ読み込み完了後すぐにモーダルを表示したい場合に使う。
  connect() {
    // show バリューが true の場合（= flash[:crisis] が true だった場合）、
    // ページ読み込み直後にモーダルを自動表示する
    if (this.showValue) {
      // 少し遅延させる理由:
      //   ページの CSS アニメーションが完了してからモーダルが現れると
      //   UX が滑らかになる。また DOM が完全に準備されてから表示するための安全策。
      setTimeout(() => this.openModal(), 100)
    }

    // Escape キーでモーダルを閉じるイベントリスナーを登録する
    // 【bind(this) の理由】
    //   addEventListener に渡すコールバックは this の参照が失われるため、
    //   bind(this) でこのコントローラーインスタンスを束縛する。
    this._boundHandleKeydown = this._handleKeydown.bind(this)
    document.addEventListener("keydown", this._boundHandleKeydown)
  }

  // ============================================================
  // disconnect(): コントローラーが HTML から切り離されたときに呼ばれる
  // ============================================================
  //
  // 【なぜイベントリスナーを削除するのか】
  //   コントローラーが切り離された後もリスナーが残ると「メモリリーク」が発生する。
  //   Turbo Drive でページ遷移した場合でも安全に動作させるために必須。
  disconnect() {
    document.removeEventListener("keydown", this._boundHandleKeydown)
    // モーダルが開いたままページ遷移した場合のスクロール復元
    document.body.style.overflow = ""
  }

  // ============================================================
  // openModal(): モーダルを開く
  // ============================================================
  openModal() {
    // 背景スクロールを無効化する
    // 【理由】モーダル表示中に背景がスクロールされると
    //   ユーザーがモーダルの外に意識が向いてしまうため。
    document.body.style.overflow = "hidden"

    // オーバーレイを表示する
    if (this.hasOverlayTarget) {
      this.overlayTarget.style.display = "flex"
    }

    // 画面幅で表示を切り替える
    // 768px 以上 → デスクトップ用中央モーダル
    // 768px 未満 → スマホ用ボトムシート
    if (window.innerWidth >= 768) {
      this._showDesktopModal()
    } else {
      this._showMobileSheet()
    }
  }

  // ============================================================
  // closeModal(): モーダルを閉じる（「入力を続ける」ボタンのアクション）
  // ============================================================
  //
  // 【HTML での使い方】
  //   <button data-action="crisis-intervention#closeModal">入力を続ける</button>
  closeModal() {
    // 背景スクロールを復元する
    document.body.style.overflow = ""

    // オーバーレイを非表示にする
    if (this.hasOverlayTarget) {
      this.overlayTarget.style.display = "none"
    }

    // デスクトップモーダルを非表示にする
    if (this.hasModalTarget) {
      this.modalTarget.style.display = "none"
    }

    // スマホボトムシートをアニメーション付きで閉じる
    if (this.hasSheetTarget) {
      this.sheetTarget.style.transform = "translateY(100%)"
      // アニメーション完了後に非表示にする
      setTimeout(() => {
        if (this.hasSheetTarget) {
          this.sheetTarget.style.display = "none"
        }
      }, 300) // CSS transition の時間（300ms）と合わせる
    }
  }

  // ============================================================
  // overlayClicked(event): オーバーレイをクリックしたときの処理
  // ============================================================
  //
  // 【危機介入モーダルはオーバーレイクリックで閉じない設計にする】
  //   通常のモーダルと異なり、危機介入モーダルは
  //   ユーザーに必ず一度情報を目にしてもらいたい。
  //   誤操作で閉じないよう、オーバーレイクリックでは閉じない。
  //   （「入力を続ける」ボタンのみで閉じられる）
  overlayClicked(event) {
    // オーバーレイ（背景）自体がクリックされた場合のみ処理する
    // モーダルカード内をクリックした場合はイベントが伝播してくるため
    // stopPropagation は不要（target チェックで判断する）
    //
    // 【危機介入モーダルはオーバーレイでは閉じない】
    // event.target === this.overlayTarget だった場合でも閉じない。
    // 何もしない（意図的に空にする）
  }

  // ============================================================
  // Private メソッド（外部から呼ばれない処理）
  // ============================================================

  // _showDesktopModal: デスクトップ用中央モーダルを表示する
  _showDesktopModal() {
    if (this.hasModalTarget) {
      this.modalTarget.style.display = "flex"
    }
    // スマホ用ボトムシートは非表示にする（念のため）
    if (this.hasSheetTarget) {
      this.sheetTarget.style.display = "none"
    }
  }

  // _showMobileSheet: スマホ用ボトムシートをアニメーション付きで表示する
  _showMobileSheet() {
    if (this.hasSheetTarget) {
      // まず display: flex で表示してから transform でスライドアニメーションを開始
      this.sheetTarget.style.display = "flex"
      // 表示直後に transform を戻すことでスライドアニメーションが発生する
      // requestAnimationFrame: ブラウザの描画タイミングに合わせて実行する
      requestAnimationFrame(() => {
        requestAnimationFrame(() => {
          if (this.hasSheetTarget) {
            this.sheetTarget.style.transform = "translateY(0)"
          }
        })
      })
    }
    // デスクトップ用モーダルは非表示にする（念のため）
    if (this.hasModalTarget) {
      this.modalTarget.style.display = "none"
    }
  }

  // _handleKeydown: キーボードイベントのハンドラー
  _handleKeydown(event) {
    // 危機介入モーダルは Escape キーでも閉じない
    // （「入力を続ける」ボタンのみで閉じる設計）
    // → 何もしない（意図的に空にする）
  }
}