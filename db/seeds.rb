# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

# Crear roles
puts "🌱 Creando roles..."

cliente_role = Role.find_or_create_by!(name: 'cliente') do |role|
  role.label = 'Cliente'
end

admin_role = Role.find_or_create_by!(name: 'admin') do |role|
  role.label = 'Administrador'
end

puts "✅ Roles creados: #{Role.count}"

# Crear usuarios de prueba
puts "🌱 Creando usuarios de prueba..."

# Usuario cliente de prueba
test_client = User.find_or_initialize_by(email: 'cliente@test.com')
if test_client.new_record?
  test_client.assign_attributes(
    name: 'Juan',
    last_name: 'Pérez',
    email: 'cliente@test.com',
    password: 'password123',
    password_confirmation: 'password123',
    phone: '+1 555-123-4567',
    number: '123456', # Número de cliente fijo para testing
    role: cliente_role
  )
  test_client.save!
  test_client.create_credit!(amount: 500.0)
  test_client.confirm # Confirmar para que pueda iniciar sesión en entorno de prueba
  puts "✅ Cliente de prueba creado: #{test_client.email} - Número: #{test_client.number}"
else
  puts "ℹ️  Cliente de prueba ya existe: #{test_client.email} - Número: #{test_client.number}"
end

# Usuario admin de prueba
test_admin = User.find_or_initialize_by(email: 'admin@test.com')
if test_admin.new_record?
  test_admin.assign_attributes(
    name: 'Admin',
    last_name: 'Sistema',
    email: 'admin@test.com',
    password: 'admin123',
    password_confirmation: 'admin123',
    role: admin_role
  )
  test_admin.save!
  test_admin.confirm # Usuarios no-clientes se confirman al crearse
  puts "✅ Admin de prueba creado: #{test_admin.email}"
else
  puts "ℹ️  Admin de prueba ya existe: #{test_admin.email}"
end

# Crear más clientes de prueba
3.times do |i|
  client_email = "cliente#{i + 1}@test.com"
  client = User.find_or_initialize_by(email: client_email)
  if client.new_record?
    client.assign_attributes(
      name: "Cliente#{i + 1}",
      last_name: 'Test',
      email: client_email,
      password: 'password123',
      password_confirmation: 'password123',
      phone: "+1 555-123-456#{i}",
      number: (100000 + i).to_s,
      role: cliente_role
    )
    client.save!
    client.create_credit!(amount: rand(100..1000).to_f)
    client.confirm # Confirmar clientes de prueba para que puedan iniciar sesión
    puts "✅ Cliente creado: #{client.email} - Número: #{client.number}"
  end
end

puts "✅ Usuarios creados: #{User.count}"
puts "✅ Créditos creados: #{Credit.count}"
puts ""
puts "🎉 Seed completado exitosamente!"
puts ""
puts "📋 Credenciales de prueba:"
puts "   Cliente: número 123456, email cliente@test.com, password password123"
puts "   Admin: email admin@test.com, password admin123"
