# frozen_string_literal: true

class Sale < ApplicationRecord
  belongs_to :customer
  has_many :sale_products, inverse_of: :sale, dependent: :destroy
  accepts_nested_attributes_for :sale_products, reject_if: :all_blank, allow_destroy: true
  enum payment_type: %i[Débito Crédito Dinheiro Débito_Dinheiro Crédito_Dinheiro Depósito Boleto]
  enum store_sale: %i[Sem_Loja PurchaseStoreRS PurchaseStoreSP]
  scope :from_store, -> (store = self.store_sales["Sem_Loja"]) {where("store_sale = ?", store)}
  def self.integrate_orders(id, store_sale)
    sale = Sale.where(order_code: id).first
    id = (id.to_i + 1).to_s
    if sale.nil?
      order = HTTParty.get("https://purchasestore.com.br/ws/wspedidos/#{id}.json?",
                           headers: { content: 'application/json',
                                      Appkey: 'ZTgyYjMzZDJhMDVjMTVjZWM4OWNiMGU5NjI1NTNkYmU' })

      customer = Customer.where(cpf: order['result']['Wspedido']['cliente_cpfcnpj'].delete('.-')).first
      customer = Customer.where(cpf: order['result']['Wspedido']['cliente_cpfcnpj']).first if customer.nil?
      if customer.nil?
        customer = Customer.create(cpf: order['result']['Wspedido']['cliente_cpfcnpj'],
                                   name: order['result']['Wspedido']['cliente_razaosocial'],
                                   cellphone: order['result']['Wspedido']['cliente_telefone'],
                                   email: order['result']['Wspedido']['cliente_email'])
      end
      if customer.present?
        sale = Sale.create(online: true,
                           customer_id: customer.id,
                           created_at: DateTime.parse(order['result']['Wspedido']['data_pedido']),
                           order_code: order['result']['Wspedido']['numero'],
                           value: order['result']['Wspedido']['total_produtos'],
                           discount: order['result']['Wspedido']['total_descontos'],
                           payment_type: order['result']['Pagamento']['integrador'] == 'Depósito Bancário' ? 'Depósito' : 'Crédito',
                           store_sale: store_sale)
        order['result']['Item'].each do |item|
          product = Product.where(sku: item['sku']).or(Product.where(extra_sku: item['sku'])).first
          if product.present?
            SaleProduct.create(quantity: item['quantidade'], value: item['valor_total'].to_f, product_id: product.id, sale_id: sale.id)
          else
            puts "Product Not Found - Pedido #{id}"
          end
        end
      else
        puts "Error Save Customer - Pedido #{id}"
      end
    else
      puts "Pedido #{id} já cadastrado"
    end
  end
end
