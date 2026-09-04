# Una comparación CRUDA por respuesta comparable de la entrevista de referencias:
# lo que el cliente declaró vs lo que la referencia contestó, con el delta CON
# SIGNO y la fuente (el empleador real nunca se mezcla con un amigo contactado
# en su propio trabajo). Se guarda todo para poder medir qué predice de verdad.
class ReferenceCheck < ApplicationRecord
  belongs_to :contract
  belongs_to :reference_ping, optional: true
end
