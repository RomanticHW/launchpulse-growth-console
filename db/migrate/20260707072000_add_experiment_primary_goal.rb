class AddExperimentPrimaryGoal < ActiveRecord::Migration[8.1]
  def change
    add_column :experiments, :primary_goal, :string, null: false, default: "form_submit"
    add_index :experiments, :primary_goal
  end
end
