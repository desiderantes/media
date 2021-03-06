/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace View {
public class Ruler : Gtk.DrawingArea {
    weak Model.TimeSystem provider;
    const int BORDER = 4;

    public signal void position_changed(int x);

    public Ruler(Model.TimeSystem provider, int height) {
        this.provider = provider;
        set_flags(Gtk.WidgetFlags.NO_WINDOW);
        set_size_request(0, height);
    }

    public override bool expose_event(Gdk.EventExpose event) {
        int x = event.area.x;
        int frame = provider.get_start_token(x);

        Cairo.Context context = Gdk.cairo_create(window);
        context.save();
        Gdk.cairo_set_source_color(context, parse_color("#777"));
        context.rectangle(event.area.x, event.area.y, event.area.width, event.area.height);
        context.fill();

        Cairo.Antialias old_antialias = context.get_antialias();

        context.set_antialias(Cairo.Antialias.NONE);
        context.set_source_rgb(1.0, 1.0, 1.0);
        int stop = event.area.x + event.area.width;
        Pango.FontDescription f = Pango.FontDescription.from_string("Sans 8");
        while (x <= stop) {
            x = provider.frame_to_xsize(frame);
            int y = provider.get_pixel_height(frame);

            context.move_to(x + BORDER, 0);
            context.line_to(x + BORDER, y);

            string? display_string = provider.get_display_string(frame);
            if (display_string != null) {
                Pango.Layout layout = Pango.cairo_create_layout(context);
                layout.set_text(display_string, (int) display_string.length);

                int w;
                int h;
                layout.set_font_description(f);
                layout.get_pixel_size (out w, out h);
                int text_pos = x - (w / 2) + BORDER;
                if (text_pos < 0) {
                    text_pos = 0;
                }
                context.move_to(text_pos, 7);
                context.set_source_rgb(1, 1, 1);
                Pango.cairo_show_layout(context, layout);
            }

            frame = provider.get_next_position(frame);
        }
        context.set_antialias(old_antialias);
        context.set_line_width(1.0);
        context.stroke();
        context.restore();
        return true;
    }

    public override bool button_press_event(Gdk.EventButton event) {
        position_changed((int) event.x);
        return false;
    }

    public override bool motion_notify_event(Gdk.EventMotion event) {
        if ((event.state & Gdk.ModifierType.BUTTON1_MASK) != 0) {
            queue_draw();
            position_changed((int) event.x);
        }
        return false;
    }
}
}
