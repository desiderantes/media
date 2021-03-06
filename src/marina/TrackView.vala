/* Copyright 2009-2010 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

using Logging;

class TrackViewConcrete : TrackView, Gtk.Fixed {
    Model.Track track;
    TimeLine timeline;
    TransportDelegate transport_delegate;

    const int clip_height = 50;
    const int TrackHeight = clip_height + TimeLine.BORDER * 2;

    public TrackViewConcrete(TransportDelegate transport_delegate, 
            Model.Track track, TimeLine timeline) {
        this.track = track;
        this.timeline = timeline;
        this.transport_delegate = transport_delegate;

        track.clip_added.connect(on_clip_added);
        track.clip_removed.connect(on_clip_removed);
    }

    public override bool expose_event(Gdk.EventExpose event) {
        Cairo.Context context = Gdk.cairo_create(window);
        Cairo.Antialias old_antialias = context.get_antialias();

        context.set_antialias(Cairo.Antialias.NONE);
        context.set_source_rgb(0.3, 0.3, 0.3);
        double old_line_width = context.get_line_width();

        context.set_line_width(2);
        int64 current_time = timeline.provider.xpos_to_time(event.area.x);
        int64 stop = timeline.provider.xpos_to_time(event.area.x + event.area.width);
        while (current_time <= stop) {
            current_time = timeline.provider.next_tick(current_time);
            int x = timeline.provider.time_to_xpos(current_time);
            context.move_to(x, allocation.y);
            context.line_to(x, allocation.y + allocation.height - 1);
        }
        context.stroke();
        context.set_line_width(1);
        context.set_source_rgb(0.5, 0.5, 0.5);
        context.move_to(event.area.x, allocation.y + allocation.height - 1);
        context.line_to(event.area.x + event.area.width, allocation.y + allocation.height - 1);

        context.stroke();
        context.set_antialias(old_antialias);
        context.set_line_width(old_line_width);
        return base.expose_event(event);
    }

    protected override void size_request(out Gtk.Requisition requisition) {
        base.size_request(out requisition);
        requisition.height = TrackHeight;
        requisition.width += TimeLine.BORDER;    // right margin
    }

    void on_clip_moved(ClipView clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_moved");
        set_clip_pos(clip);
    }

    void on_clip_deleted(Model.Clip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_deleted");
        track.delete_clip(clip);
        clear_drag();
    }

    void on_clip_added(Model.Track t, Model.Clip clip, bool select) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_added");
        ClipView view = new ClipView(transport_delegate, clip, timeline.provider, clip_height);
        view.clip_moved.connect(on_clip_moved);
        view.clip_deleted.connect(on_clip_deleted);
        view.move_begin.connect(on_move_begin);
        view.trim_begin.connect(on_trim_begin);

        put(view, timeline.provider.time_to_xpos(clip.start), TimeLine.BORDER);
        view.show();

        timeline.track_changed();
        clip_view_added(view);
        if (select) {
            view.selection_request(ClipView.SelectionType.NONE);
        }
    }

    // TODO: This method should not be public.  When linking/grouping is done, this method
    // should become private.  See Timeline.on_clip_view_move_begin for more information.
    public void move_to_top(ClipView clip_view) {
        /*
        * We remove the ClipView from the Fixed object and add it again to make
        * sure that when we draw it, it is displayed above every other clip while
        * dragging.
        */
        remove(clip_view);
        put(clip_view, 
            timeline.provider.time_to_xpos(clip_view.clip.start),
            TimeLine.BORDER);
        clip_view.show();
    }

    void on_trim_begin(ClipView clip_view, Gdk.WindowEdge edge) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_trim_begin");
        move_to_top(clip_view);
    }

    void on_move_begin(ClipView clip_view, bool do_copy) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_move_begin");
        move_to_top(clip_view);
    }

    void set_clip_pos(ClipView view) {
        move(view, timeline.provider.time_to_xpos(view.clip.start), TimeLine.BORDER);
        queue_draw();
    }

    public void resize() {
        foreach (Gtk.Widget w in get_children()) {
            ClipView view = w as ClipView;
            if (view != null) {
                view.on_clip_moved(view.clip);
            }
        }
    }

    void on_clip_removed(Model.Clip clip) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_clip_removed");
        foreach (Gtk.Widget w in get_children()) {
            ClipView view = w as ClipView;
            if (view.clip == clip) {
                view.clip_moved.disconnect(on_clip_moved);
                remove(view);
                timeline.track_changed();
                return;
            }
        }
    }

/*
    void unselect_gap() {
        if (timeline.gap_view != null) {
            TrackView parent = timeline.gap_view.parent as TrackView;
            parent.remove(timeline.gap_view);
            timeline.gap_view = null;
        }
    }
*/

    protected override bool button_press_event(Gdk.EventButton e) {
        if (e.type != Gdk.EventType.BUTTON_PRESS &&
            e.type != Gdk.EventType.2BUTTON_PRESS &&
            e.type != Gdk.EventType.3BUTTON_PRESS)
            return false;

        if (e.button == 1 ||
            e.button == 3) {
/*
            int x = (int) e.x;
            int64 time = timeline.provider.xpos_to_time(x);
            Model.Gap g;
            track.find_containing_gap(time, out g);
            if (g.end > g.start) {
                int64 length = g.end - g.start;
                int width = timeline.provider.time_to_xpos(g.start + length) -
                    timeline.provider.time_to_xpos(g.start);            
                
                timeline.gap_view = new GapView(g.start, length, 
                    width, clip_height);
                timeline.gap_view.removed += on_gap_view_removed;
                timeline.gap_view.unselected += on_gap_view_unselected;
                put(timeline.gap_view, timeline.provider.time_to_xpos(g.start), TimeLine.BORDER);
                timeline.gap_view.show();
            }
*/
            timeline.deselect_all_clips();
        }
        return false;
    }
/*
    void on_gap_view_removed(GapView gap_view) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_gap_view_removed");
        track.delete_gap(gap_view.gap);
    }

    void on_gap_view_unselected(GapView gap_view) {
        emit(this, Facility.SIGNAL_HANDLERS, Level.INFO, "on_gap_view_unselected");
        unselect_gap();
    }
*/
    void clear_drag() {
        window.set_cursor(null);
        queue_draw();
    }

    public Model.Track get_track() {
        return track;
    }
    
    public int get_track_height() {
        return TrackHeight;
    }
    
    public Gtk.Widget? find_child(double x, double y) {
        foreach (Gtk.Widget w in get_children()) {
            if (w.allocation.x <= x && x < w.allocation.x + w.allocation.width) {
                return w;
            }
        }
        return null;
    }
    
    public void select_all() {
        foreach (Gtk.Widget child in get_children()) {
            ClipView? clip_view = child as ClipView;
            if (clip_view != null) {
                clip_view.select();
            }
        }
    }
}
