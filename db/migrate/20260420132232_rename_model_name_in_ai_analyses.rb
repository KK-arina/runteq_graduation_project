# db/migrate/XXXXXX_rename_model_name_in_ai_analyses.rb
class RenameModelNameInAiAnalyses < ActiveRecord::Migration[7.2]
  def change
    # model_name → ai_model_name にリネームする
    # 【理由】
    #   model_name は ActiveRecord が内部で使用している予約済みメソッド名。
    #   カラム名と衝突すると ActiveRecord::DangerousAttributeError が発生する。
    #   ai_model_name に変更することで衝突を回避する。
    rename_column :ai_analyses, :model_name, :ai_model_name
  end
end