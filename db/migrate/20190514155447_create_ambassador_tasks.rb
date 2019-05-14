class CreateAmbassadorTasks < ActiveRecord::Migration
  def change
    create_table :ambassador_tasks do |t|
      t.string :description, null: false, default: ""
      t.boolean :completed, null: false, default: false
      t.belongs_to :user, index: true, null: false

      t.timestamps null: false
    end

    add_foreign_key :ambassador_tasks, :users, on_delete: :cascade
  end
end
