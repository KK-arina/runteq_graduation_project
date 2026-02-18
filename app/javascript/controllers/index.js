// ==============================================================================
// app/javascript/controllers/index.js
// ==============================================================================
// 【役割】
//   このファイルは全ての Stimulus コントローラーを自動登録する。
//   eagerLoadControllersFrom はディレクトリを監視し、
//   コントローラーファイルを自動でインポート・登録する。
//
// 【自動登録の仕組み】
//   app/javascript/controllers/habit_record_controller.js
//   → コントローラー名: "habit-record"（アンダースコア→ハイフン変換）
//   → HTML: data-controller="habit-record" で使用可能になる
//
// 【Rails 7 のデフォルト設定】
//   Rails 7 では importmap を使うため、このファイルはデフォルトで存在する。
//   新しいコントローラーを追加した場合、このファイルの変更は不要。
//   （eagerLoadControllersFrom が自動検出する）
// ==============================================================================
import { application } from "./application"
import { eagerLoadControllersFrom } from "@hotwired/stimulus-loading"

// app/javascript/controllers/ 以下のファイルを全て読み込む
eagerLoadControllersFrom("controllers", application)
