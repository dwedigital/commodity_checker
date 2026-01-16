class AddBodyHtmlToInboundEmails < ActiveRecord::Migration[8.0]
  def change
    add_column :inbound_emails, :body_html, :text
  end
end
