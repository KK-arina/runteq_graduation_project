// app/javascript/controllers/dismissible_controller.js
//
// ==============================================================================
// DismissibleController（G-7 追加 / H-9 拡張）
// ==============================================================================
//
// 【このファイルの役割】
//   バナーや通知パネルを「×ボタン」で非表示にする汎用 Stimulus コントローラー。
//   G-7 のダッシュボード PMVV 完了バナーで使用する。
//
// 【H-9 での拡張内容】
//   ✖ で閉じたときに「閉じた状態」をサーバーへ保存できるようにした。
//   data-dismissible-dismiss-url-value にURLが指定されている場合のみ、
//   hide() の中でそのURLへ fetch（PATCH）を送る。
//   これにより、リロード後もバナーが復元されなくなる（✖まで残す要件を満たす）。
//   URLが未指定の既存の使い方では従来どおり「hiddenにするだけ」で動作する（後方互換）。
//
// ==============================================================================

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // static values: このコントローラーが受け取るオプション値の定義
  //   dismissUrl    : ✖押下時に閉じた状態を保存するURL（空なら保存しない＝後方互換）
  //   dismissMethod : 保存リクエストのHTTPメソッド（既定は patch）
  static values = {
    dismissUrl:    String,
    dismissMethod: { type: String, default: "patch" }
  }

  // connect(): Stimulus がこの要素に接続するたびに呼ばれる。
  // Turbo Stream が replace した後も呼ばれるため、
  // hidden クラスを確実に除去してバナーを表示状態にする。
  connect() {
    this.element.classList.remove("hidden")
  }

  // hide(): ✖ボタンから呼ばれる。まず即座に非表示にし、続けてサーバーへ保存する。
  hide() {
    // ① まず見た目を閉じる（サーバー保存の成否に関わらずUIは即座に閉じる）
    this.element.classList.add("hidden")
    // ② 閉じた状態をサーバーへ永続化する（URLが設定されている場合のみ）
    this.persistDismissal()
  }

  // persistDismissal(): 閉じた状態をサーバーに保存する。
  persistDismissal() {
    // dismissUrl が未設定（従来の使い方）なら何もしない＝後方互換
    if (!this.hasDismissUrlValue || this.dismissUrlValue === "") return

    // Rails の CSRF トークンを meta タグから取得する（POST/PATCH に必須）
    const token = document.querySelector('meta[name="csrf-token"]')?.content

    fetch(this.dismissUrlValue, {
      method:  this.dismissMethodValue.toUpperCase(),
      headers: {
        "X-CSRF-Token": token,
        "Accept":       "application/json"
      },
      // 同一オリジンのセッションクッキーを送るために必要
      credentials: "same-origin"
    }).catch((error) => {
      // 保存に失敗してもUI上は閉じたまま維持する。
      // （次回リロードで復活する可能性はあるが、致命的ではないためログのみ）
      console.warn("[dismissible] 閉じ状態の保存に失敗しました:", error)
    })
  }
}