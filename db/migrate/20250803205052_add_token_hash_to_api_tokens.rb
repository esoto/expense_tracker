class AddTokenHashToApiTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :api_tokens, :token_hash, :string
    add_index :api_tokens, :token_hash, unique: true

    # Note: We cannot backfill token_hash for existing tokens because
    # we don't have access to the original plain-text tokens.
    # Existing tokens will need to be regenerated or will continue
    # using the old authentication method as a fallback.
  end
end
