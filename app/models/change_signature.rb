# frozen_string_literal: true

# Firma de un administrador sobre un cambio propuesto (queda guardada SIEMPRE,
# aunque el cambio se aplique, se rechace o el usuario se elimine después).
class ChangeSignature < ApplicationRecord
  belongs_to :change_request
end
