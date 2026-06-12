// app/javascript/controllers/dismissible_controller.js
//
// ==============================================================================
// DismissibleController（G-7 追加）
// ==============================================================================
//
// 【このファイルの役割】
//   バナーや通知パネルを「×ボタン」で非表示にする汎用 Stimulus コントローラー。
//   G-7 のダッシュボード PMVV 完了バナーで使用する。
//
// 【_pmvv_completion_banner.html.erb との関係】
//   このコントローラーは「内側のバナー本体 div」に付けることで、
//   外側の id="dashboard_pmvv_completion_banner" div を hidden にせず保護する設計になっている。
//   この設計により、×で閉じた後も Turbo Stream が次回のブロードキャスト先を
//   正しく発見でき、再通知が機能し続ける。
//
// 【なぜ新しいコントローラーを作るのか】
//   既存の flash_controller.js は「タイムアウトで自動非表示」する機能を持ち、
//   フラッシュメッセージ専用の設計になっている。
//   Turbo Stream で差し替えられるバナーに使うと自動タイムアウトが
//   邪魔になる可能性があるため、シンプルな「手動で閉じるだけ」の
//   コントローラーを別途作成する。
//
// 【汎用設計にする理由】
//   今後、別の「×で閉じられるバナー」が追加されたときにも
//   このコントローラーをそのまま再利用できる。
//
// ==============================================================================

// Stimulus の Controller クラスをインポートする。
// Stimulus はモジュール形式（ES Modules）で書かれているため、
// import しないと Controller クラスが見つからずエラーになる。
import { Controller } from "@hotwired/stimulus"

// export default: このクラスを外部から使えるようにする宣言。
// app/javascript/controllers/index.js が各コントローラーを
// import して Stimulus に登録するため、export が必要。
export default class extends Controller {

  // hide(): data-action="click->dismissible#hide" が呼び出すメソッド
  //
  // 【this.element とは】
  //   Stimulus では data-controller="dismissible" が付いた HTML 要素が
  //   this.element として参照できる。
  //   _pmvv_completion_banner.html.erb では「内側のバナー本体 div」を指す。
  //   外側の id="dashboard_pmvv_completion_banner" div ではない点が重要。
  //
  // 【classList.add("hidden") とは】
  //   Tailwind CSS の "hidden" クラスは display: none; に相当する。
  //   クラスを追加することで要素を視覚的に非表示にできる。
  //
  // 【なぜ内側の div だけを hidden にするのか】
  //   外側の id="dashboard_pmvv_completion_banner" div は
  //   Turbo Stream の broadcast_replace_to が差し替え先を探すための目印（ターゲット）。
  //   もし外側の div が hidden になると、次回分析完了時に
  //   Turbo Stream がターゲットを見つけられずに通知が届かなくなる。
  //   内側の div だけを hidden にすることで、外側の div は常に DOM に残り、
  //   次回通知も確実に受け取れる設計になる。
  //
  // 【なぜ remove() を使わないのか】
  //   remove() は DOM から要素を完全に削除してしまう。
  //   Turbo Stream はターゲット id を DOM で検索するため、
  //   要素が消えていると差し替えができなくなる。
  //   hidden クラスで「見えないが DOM には残る」状態にする方が安全。
  hide() {
    this.element.classList.add("hidden")
  }
}