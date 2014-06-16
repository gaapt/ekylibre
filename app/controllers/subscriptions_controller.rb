# -*- coding: utf-8 -*-
# == License
# Ekylibre - Simple ERP
# Copyright (C) 2008-2011 Brice Texier, Thibaud Merigon
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

class SubscriptionsController < ApplicationController
  manage_restfully :contact_id=>"@current_company.contacts.find_by_entity_id(params[:entity_id]).id rescue 0", :sale_line_id=>"@current_company.sale_lines.find_by_id(params[:sale_line_id]).id rescue nil", :entity_id=>"@current_company.entities.find(params[:entity_id]).id rescue 0", :nature_id=>"@current_company.subscription_natures.first.id rescue 0", :t3e=>{:nature=>"@subscription.nature.name", :start=>"@subscription.start", :finish=>"@subscription.finish"}

  def self.subscriptions_conditions(options={})
    code = ""
    code += "conditions = [ \" #{Subscription.table_name}.company_id = ? AND COALESCE(#{Subscription.table_name}.sale_id, 0) NOT IN (SELECT id FROM #{Sale.table_name} WHERE company_id = ? and state NOT IN ('invoice', 'order'))\" , @current_company.id, @current_company.id]\n"
    code += "unless session[:subscriptions_nature_id].to_i.zero?\n"
    code += "  conditions[0] += \" AND #{Subscription.table_name}.nature_id = ?\"\n"
    code += "  conditions << session[:subscriptions_nature_id].to_i\n"
    code += "end\n"
    code += "unless session[:subscriptions_instant].nil?\n"
    code += "  if session[:subscriptions_nature_nature] == 'quantity'\n"
    code += "    conditions[0] += \" AND ? BETWEEN #{Subscription.table_name}.first_number AND #{Subscription.table_name}.last_number\"\n"
    code += "  elsif session[:subscriptions_nature_nature] == 'period'\n"
    code += "    conditions[0] += \" AND ? BETWEEN #{Subscription.table_name}.started_on AND #{Subscription.table_name}.stopped_on\"\n"
    code += "  end\n"
    code += "  conditions << session[:subscriptions_instant]\n"
    code += "end\n"
    code += "conditions\n"
    code
  end

  list(:conditions=>subscriptions_conditions, :order=> "id DESC") do |t|
    t.column :full_name, :through=>:entity, :url=>true
    t.column :line_2, :through=>:contact, :label=>:column
    t.column :line_3, :through=>:contact, :label=>:column
    t.column :line_4, :through=>:contact, :label=>:column
    t.column :line_5, :through=>:contact, :label=>:column
    t.column :line_6_code, :through=>:contact, :label=>:column
    t.column :line_6_city, :through=>:contact, :label=>:column
    t.column :name, :through=>:product
    t.column :quantity
    t.column :start
    t.column :finish
  end

  # Displays the main page with the list of subscriptions
  def index
    if @current_company.subscription_natures.size.zero?
      notify(:need_to_create_subscription_nature)
      redirect_to :controller=>:subscription_natures
      return
    end
    if request.xhr?
      return unless @subscription_nature = find_and_check(:subscription_nature, params[:nature_id])
      session[:subscriptions_instant] = @subscription_nature.now
      render :partial=>"options"
      return
    end
    if params[:nature_id]
      return unless @subscription_nature = find_and_check(:subscription_nature, params[:nature_id])
    end
    @subscription_nature ||= @current_company.subscription_natures.first
    instant = (@subscription_nature.period? ? params[:instant].to_date : params[:instant].to_i) rescue nil 
    session[:subscriptions_nature_id]  = @subscription_nature.id
    session[:subscriptions_nature_nature] = @subscription_nature.nature
    session[:subscriptions_instant] = ((instant.blank? or instant == 0) ? @subscription_nature.now : instant)
  end


  def coordinates
    nature, attributes = nil, {}
    if params[:nature_id]
      return unless nature = find_and_check(:subscription_nature, params[:nature_id])
    elsif params[:price_id]
      return unless price = find_and_check(:price, params[:price_id])
      if price.product.subscription?
        nature = price.product.subscription_nature 
        attributes[:product_id] = price.product_id
      end
    end
    if nature
      attributes[:contact_id] = (@current_company.contacts.find_by_entity_id(params[:entity_id]).id rescue 0)
      @subscription = nature.subscriptions.new(attributes)
      @subscription.compute_period
    end
    mode = params[:mode]||:coordinates
    render :partial=>"#{mode}_form"
  end

end