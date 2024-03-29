# frozen_string_literal: true

module BroadcastMessagesHelper
  def broadcast_message(message)
    return unless message.present?

    content_tag :div, class: 'broadcast-message', style: broadcast_message_style(message) do
      icon('bullhorn') << ' ' << render_broadcast_message(message)
    end
  end

  def broadcast_message_style(broadcast_message)
    style = []

    if broadcast_message.color.present?
      style << "background-color: #{broadcast_message.color}"
    end

    if broadcast_message.font.present?
      style << "color: #{broadcast_message.font}"
    end

    style.join('; ')
  end

  def broadcast_message_status(broadcast_message)
    if broadcast_message.active?
      '当前'
    elsif broadcast_message.ended?
      '已过期'
    else
      '排队'
    end
  end

  def render_broadcast_message(broadcast_message)
    Banzai.render_field(broadcast_message, :message).html_safe
  end
end
