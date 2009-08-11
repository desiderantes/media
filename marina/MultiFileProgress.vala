/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

// TODO: Is this the best way to do this?
interface MultiFileProgressInterface {
    signal void fraction_updated(double d);
    signal void file_updated(string filename, int index);
    signal void done();
    
    protected abstract void on_cancel();
    protected abstract void on_complete();
}

// TODO: Rework the complete signal

class MultiFileProgress : Gtk.Window {
    Gtk.ProgressBar progress_bar;
    Gtk.Label file_label;
    Gtk.Label number_label;
    Gtk.Button cancel_button;
    int num_files;
  
    string dialog_title;
  
    signal void cancelled();
    signal void complete();

    public MultiFileProgress(Gtk.Window parent, int num_files, 
        string dialog_title, MultiFileProgressInterface provider_interface) {
        this.num_files = num_files;
        
        file_label = new Gtk.Label("");
        number_label = new Gtk.Label("");
        progress_bar = new Gtk.ProgressBar();
        
        Gtk.VBox vbox = new Gtk.VBox(true, 0);
        
        vbox.pack_start(number_label, false, false, 0);
        vbox.pack_start(file_label, false, false, 0);
        vbox.pack_start(progress_bar, false, false, 0);
        
        Gtk.HButtonBox button_area = new Gtk.HButtonBox();
        button_area.set("layout-style", Gtk.ButtonBoxStyle.CENTER); 
        
        cancel_button = new Gtk.Button.from_stock(Gtk.STOCK_CANCEL);
        cancel_button.clicked += on_cancel_clicked;
        
        button_area.add(cancel_button);
        
        vbox.pack_start(button_area, false, false, 0);

        set_border_width(8);
        set_resizable(false);
        set_transient_for(parent);        
        set_modal(true);
        set_title(dialog_title);     
        
        destroy += on_destroy;
        this.dialog_title = dialog_title;
        
        add(vbox);
        show_all();
        
        provider_interface.fraction_updated += on_fraction_updated;
        provider_interface.file_updated += on_file_updated;
        provider_interface.done += on_done;
        
        cancelled += provider_interface.on_cancel;
        complete += provider_interface.on_complete;
    }

    void on_done() {
        destroy();
    }
    
    void on_cancel_clicked() {
        destroy();
    }
    
    void on_destroy() {
        if (progress_bar.get_fraction() < 1.0)
            cancelled();
        else
            complete();
    }
    
    void on_fraction_updated(double d) {
        progress_bar.set_fraction(d);
        
        if (progress_bar.get_fraction() == 1.0)
            destroy();
        else {
            show_all();
            queue_draw();
        }
    }

    void on_file_updated(string filename, int index) {
        number_label.set_text("%sing %d of %d".printf(dialog_title, index + 1, num_files));
        file_label.set_text("%s".printf(filename));
    }
}
