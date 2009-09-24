/* Copyright 2009 Yorba Foundation
 *
 * This software is licensed under the GNU Lesser General Public License
 * (version 2.1 or later).  See the COPYING file in this distribution. 
 */

namespace Model {

public abstract class Track {
    protected weak Project project;
    protected Gee.ArrayList<Clip> clips = new Gee.ArrayList<Clip>();  // all clips, sorted by time
    public string display_name;
    bool is_selected;
    
    protected Gst.Bin composition;
    
    protected Gst.Element default_source;
    protected Gst.Element sink;    
    
    public signal void pad_added(Track track, Gst.Bin bin, Gst.Pad pad);
    public signal void pad_removed(Track track, Gst.Bin bin, Gst.Pad pad);
    public signal void clip_added(Clip clip);
    public signal void clip_removed(Clip clip);

    public signal void track_renamed(Track track);
    public signal void track_selection_changed(Track track);
    public signal void error_occurred(string major_error, string? minor_error);

    public Track(Project project, string display_name) {
        this.project = project;
        this.display_name = display_name;

        error_occurred += project.on_error_occurred;

        composition = (Gst.Bin) make_element_with_name("gnlcomposition", display_name);
        
        default_source = make_element_with_name("gnlsource", "track_default_source");
        Gst.Bin default_source_bin = (Gst.Bin) default_source;
        if (!default_source_bin.add(empty_element()))
            error("can't add empty element");

        // If we set the priority to 0xffffffff, then Gnonlin will treat this source as
        // a default and we won't be able to seek past the end of the last region.
        // We want to be able to seek into empty space, so we use a fixed priority instead.
        default_source.set("priority", 1);
        default_source.set("start", 0 * Gst.SECOND);
        default_source.set("duration", 1000000 * Gst.SECOND);
        default_source.set("media-start", 0 * Gst.SECOND);
        default_source.set("media-duration", 1000000 * Gst.SECOND);
        
        if (!composition.add(default_source))
            error("can't add default source");
  
        project.pipeline.add(composition);
        composition.pad_added += on_pad_added;
        composition.pad_removed += on_pad_removed;
        project.pre_export += on_pre_export;
        project.post_export += on_post_export;
    }
    
    ~Track() {
        if (composition != null && !project.pipeline.remove(composition)) {
            error("couldn't remove composition");
        }
    }

    protected abstract string name();
    public abstract MediaType media_type();

    protected abstract Gst.Element empty_element();
    public abstract void link_new_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element);
    public abstract void unlink_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element);

    public void hide() {
        project.pipeline.remove(composition);
        composition = null;
    }

    void on_pre_export() {
        default_source.set("duration", project.get_length());
        default_source.set("media-duration", project.get_length());    
    }
    
    void on_post_export() {
        default_source.set("duration", 1000000 * Gst.SECOND);
        default_source.set("media-duration", 1000000 * Gst.SECOND);
    }

    public bool contains_clipfile(ClipFile f) {
        foreach (Clip c in clips) {
            if (c.clipfile == f)
                return true;
        }
        return false;
    }

    protected abstract bool check(Clip clip);

    void on_pad_removed (Gst.Bin bin, Gst.Pad pad) {
        pad_removed(this, bin, pad);
    }

    void on_pad_added(Gst.Bin bin, Gst.Pad pad) {
        pad_added(this, bin, pad);
    }
  
    public int64 get_time_from_pos(int pos, bool after) {
        if (after)
            return clips[pos].start + clips[pos].length;
        else
            return clips[pos].start;
    }

    public int get_clip_from_time(int64 time) {
        for (int i = 0; i < clips.size; i++) {
            if (time >= clips[i].start &&
                time < clips[i].end)
                return i;
        }
        return -1;
    }
    
    public bool snap_clip(Clip c, int64 span) {
        foreach (Clip cl in clips) {
            if (c.snap(cl, span))
                return true;
        }
        return false;
    }
    
    public bool snap_coord(out int64 coord, int64 span) {
        foreach (Clip c in clips) {
            if (c.snap_coord(out coord, span))
                return true;
        }
        return false;
    }
    
    int get_insert_index(int64 time) {
        int end_ret = 0;
        for (int i = 0; i < clips.size; i++) {
            Clip c = clips[i];
       
            if (time >= c.start) {
                if (time < c.start + c.length/2)
                    return i;
                else if (time < c.start + c.length)
                    return i + 1;
                else
                    end_ret ++;
            }
        }
        return end_ret;
    }

    // This is called to find the first gap after a start time
    public Gap find_first_gap(int64 start) {
        int64 new_start = 0;
        int64 new_end = int64.MAX;
        
        foreach (Clip c in clips) {
            if (c.start > new_start &&
                c.start > start) {
                new_end = c.start;
                break;
            }
            new_start = c.end;
        }
        return new Gap(new_start, new_end);
    }

    // This is always called with the assumption that we are not on a clip
    public int get_gap_index(int64 time) {
        int i = 0;
        while (i < clips.size) {
            if (time <= clips[i].start)
                break;
            i++;
        }
        return i;
    }
    
    // If we are not on a valid gap (as in, a space between two clips or between the start
    // and the first clip), we return an empty (and invalid) gap
    public void find_containing_gap(int64 time, out Gap g) {
        g = new Gap(0, 0);
        
        int index = get_gap_index(time);
        if (index < clips.size) {
            g.start = index > 0 ? clips[index - 1].end : 0;
            g.end = clips[index].start;
        }
    }
    
    public int find_overlapping_clip(int64 start, int64 length) {
        for (int i = 0; i < clips.size; i++) {
            Clip c = clips[i];
            if (c.overlap_pos(start, length))
                return i;
        }
        return -1;
    }

    public int find_nearest_clip_edge(int64 time, out bool after) {
        int limit = clips.size * 2;
        int64 prev_time = clips[0].start;
        
        for (int i = 1; i < limit; i++) {
            Clip c = clips[i / 2];
            int64 t;
            
            if (i % 2 == 0)
                t = c.start;
            else
                t = c.end;
                
            if (t > time) {
                if (t - time < time - prev_time) {
                    after = ((i % 2) != 0);
                    return i / 2;
                } else {
                    after = ((i % 2) == 0);
                    return (i - 1) / 2;
                }
            }
            prev_time = t;
        }
    
        after = true;
        return clips.size - 1;
    }
    
    void do_clip_overwrite(Clip c) {
        int start_index = get_clip_from_time(c.start);
        int end_index = get_clip_from_time(c.end);
        
        if (end_index >= 0) {
            int64 diff = c.end - clips[end_index].start;
            if (end_index == start_index) {
                if (diff > 0) {
                    Clip cl = new Clip(clips[end_index].clipfile, clips[end_index].type, 
                                    clips[end_index].name, c.end, 
                                    clips[end_index].media_start + diff,
                                    clips[end_index].length - diff);
                    put(end_index + 1, cl);
                }
            } else {
                clips[end_index].set_media_start(clips[end_index].media_start + 
                                                        diff);
                clips[end_index].set_duration(clips[end_index].length - 
                                                        diff);
                clips[end_index].set_start(c.end);
            }
        }
        if (start_index >= 0) {
            clips[start_index].set_duration(c.start - clips[start_index].start);
        }

        int i = 0;
        while (i < clips.size) {
            if (clips[i].start >= c.start &&
                clips[i].end <= c.end)
                remove_clip(i);
            else
                i++;
        }        
    }    
    
    public void add_clip_at(Clip c, int64 pos, bool overwrite, int64 original_time) {
        Command command = new ClipAddCommand(this, c, original_time, pos, overwrite);
        project.do_command(command);
    }
    
    public void _add_clip_at(Clip c, int64 pos, bool overwrite) {
        if (pos < 0) {
            pos = 0;
        }
        
        c.set_start(pos);
        if (overwrite)
            do_clip_overwrite(c);    
        
        clips.insert(get_insert_index(c.start), c);
        project.reseek();
    }

    // This function adds a new clip to the timeline; in that it adds it to
    // the Gnonlin composition and also adds a new ClipView object
    public void add_new_clip(Clip c, int64 pos, bool overwrite) {
        c.updated += on_clip_updated;
        if (!check(c))
            return;
        
        if (c.clipfile.is_online()) {
            if (composition != null) {
                composition.add(c.file_source);
            }
        }
        _add_clip_at(c, pos, overwrite);
        clip_added(c);
    }
    
    void on_clip_updated(Clip c) {
        if (c.clipfile.is_online()) {
            if (composition != null) {
                composition.add(c.file_source);
            }            
        } else {
            if (composition != null) {
                composition.remove(c.file_source);
            }    
        }
    }

    public void ripple_delete(int64 length, int64 clip_start, int64 clip_length) {
        if (find_overlapping_clip(clip_start, clip_length) != -1)
            return;
        shift_clips(get_insert_index(clip_start), -length);
    }

    public void ripple_paste(int64 length, int64 position) {
        int index = get_clip_from_time(position);
        
        if (index < 0 ||
            position == clips[index].start) {
            index = get_gap_index(position);
            shift_clips(index, length);
        }
        project.reseek();
    }

    /*
     * This function can be called with a clip that already has a clipview
     * object in the timeline.  If so, we don't want to add another one, so we
     * check for this and change the function call accordingly
    */
    public int do_clip_paste(Clip clip, int64 position, bool over, bool new_clip) {
        if (over ||
            find_overlapping_clip(position, clip.length) == -1) {
            
             if (new_clip)
                add_new_clip(clip, position, true);
             else
                _add_clip_at(clip, position, true);
                
             return 0;
        } else {
            int pos = get_clip_from_time(position);
            if (pos != -1 &&
                position != clips[pos].start) {
                return -1;
            }
            
            pos = get_insert_index(position);
            
            if (new_clip)
                insert(pos, clip, position);
            else
                insert_at(pos, clip, position);

            return 1;
        }
    }
    
    public Clip? get_clip(int i) {
        if (i < 0 || i >= clips.size)
            error("get_clip: Invalid index! %d (%d)", i, clips.size);
        return clips[i];
    }

    public int get_clip_index(Clip c) {
        for (int i = 0; i < clips.size; i++) {
            if (clips[i] == c)
                return i;
        }
        return -1;
    }
    
    public Clip? get_clip_by_position(int64 pos) {
        int length = clips.size;
        
        for (int i = length - 1; i >= 0; i--)
            if (clips[i].start < pos)
                return pos >= clips[i].end ? null : clips[i];
        return null;
    }
    
    public int64 get_length() {
        return clips.size == 0 ? 0 : clips[clips.size - 1].start + clips[clips.size - 1].length;
    }

    /* We need to set the start position of each clip
     * as this works around a current Gnonlin bug where
     * if you arrange clips a few times, the current
     * position will become corrupted.
     */
    public void shift_clips(int index, int64 shift) {
        for (int i = 0; i < clips.size; i++)
            clips[i].set_start(i >= index ? clips[i].start + shift
                                          : clips[i].start);
    }
    
    void insert_at(int i, Clip clip, int64 pos) {
        clip.set_start(pos);
        clips.insert(i, clip);
        
        shift_clips(i + 1, clip.length);
    }
    
    public void insert(int index, Clip clip, int64 pos) {
        if (check(clip)) {
            // I reversed the following two lines as shift_clips sets information on
            // clips that aren't yet in the composition otherwise, which causes behavior
            // like the position in the composition being incorrect when we start playing.
            // This also fixes the lockup problem we were having.
            if (composition != null) {
                composition.add(clip.file_source);         
                insert_at(index, clip, pos);
                
                clip_added(clip);
            }
        }
    }
    
    void put(int index, Clip c) {
        if (check(c)) {
            composition.add(c.file_source);
            clips.insert(index, c);
            
            project.reseek();
            clip_added(c);
        }
    }
    
    public void _append_at_time(Clip c, int64 time) {
        insert(clips.size, c, time);
    }
    
    public void append_at_time(Clip c, int64 time) {
        Command command = new ClipCommand(ClipCommand.Action.APPEND, this, c, time, true);
        project.do_command(command);
    }
    
    void remove_clip_at(int index) {
        int64 length = clips[index].length;
        clips.remove_at(index);
        shift_clips(index, -length);
    }
    
    public void delete_clip(Clip clip, bool ripple) {
        Command clip_command = new ClipCommand(ClipCommand.Action.DELETE, 
            this, clip, clip.start, ripple);
        project.do_command(clip_command);
    }
    
    public void _delete_clip(Clip clip, bool ripple) {
        composition.remove(clip.file_source);
        clip.file_source.set_state(Gst.State.NULL);
        int index = get_clip_index(clip);
        
        remove_clip_at(index);
        if (!ripple) {
            shift_clips(index, clip.length);
        }
        
        clip_removed(clip);
    }
    
    public void remove_clip(int index) {
        composition.remove(clips[index].file_source);
        clip_removed(clips[index]);
        clips.remove_at(index);
    }
    
    public void delete_gap(Gap g) {
        shift_clips(get_gap_index(g.start), -(g.end - g.start));
        project.reseek();
    }
    
    public void remove_clip_from_array(int pos) {
        clips.remove_at(pos);
    }
    
    /*
     * Shift the clips after index, insert the clip that was at index
     * at dest, and set its position correctly.
     * The do_shift bool is there since copy-drag rotations don't need shifts
     * as the clip to be inserted originates on top of another clip
    */
    public void rotate_clip(Clip c, int index, int dest, bool after) {
        shift_clips(index, -c.length);
        
        if (after)
            insert_at(dest + 1, c, clips[dest].start + clips[dest].length);
        else {
            int64 prev_time = clips[dest].start;
            insert_at(dest, c, prev_time);
        }
        project.reseek();
    }
    
    public void delete_all_clips() {
        uint size = clips.size;
        for (int i = 0; i < size; i++) { 
            delete_clip(clips[0], false);
        }
        project.go(0);
    }
    
    public void revert_to_original(Clip clip) {
        Command command = new ClipRevertCommand(this, clip);
        project.do_command(command);
    }
    
    public void _revert_to_original(Clip c) {    
        int index = get_clip_index(c);
        if (index == -1)
            error("revert_to_original: Clip not in track array!");
            
        shift_clips(index + 1, c.clipfile.length - c.length);       
    
        c.set_duration(c.clipfile.length);
        c.set_media_start(0);

        project.go(c.start);
    }
    
    public bool are_contiguous_clips(int64 position) {
        Clip right_clip = get_clip_by_position(position + 1);
        Clip left_clip = get_clip_by_position(position - 1);
        
        return left_clip != null && right_clip != null && 
            left_clip != right_clip &&
            left_clip.clipfile == right_clip.clipfile &&
            left_clip.end == right_clip.start;
    }
    
    public void split_at(int64 position) {
        Command command = new ClipSplitCommand(ClipSplitCommand.Action.SPLIT, this, position);
        project.do_command(command);
    }
    
    public void _split_at(int64 position) {
        Clip c = get_clip_by_position(position);
        if (c == null)
            return;
        
        Clip cn = new Clip(c.clipfile, c.type, c.name, position,
                           (position - c.start) + c.media_start, c.start + c.length - position);
        
        c.set_duration(position - c.start);                     
        
        int index = get_clip_index(c) + 1;
        shift_clips(index, -cn.length);
        insert(index, cn, position);  
    }  
    
    public void join(int64 position) {
        Command command = new ClipSplitCommand(ClipSplitCommand.Action.JOIN, this, position);
        project.do_command(command);
    }
    
    public void _join(int64 position) {
        assert(are_contiguous_clips(position));
        if (are_contiguous_clips(position)) {
            Clip right_clip = get_clip_by_position(position + 1);
            assert(right_clip != null);
        
            int right_clip_index = get_clip_index(right_clip);
            assert(right_clip_index > 0);
            
            int left_clip_index = right_clip_index - 1;
            Clip left_clip = get_clip(left_clip_index);
            assert(left_clip != null);
            left_clip.set_duration(right_clip.end - left_clip.start);
            remove_clip(right_clip_index);
        }
    }
    
    public void trim(Clip clip, int64 delta, bool left) {
        Command command = new ClipTrimCommand(this, clip, delta, left);
        project.do_command(command);
    }
    
    public void _trim(Clip c, int64 delta, bool left) {
        int index = get_clip_index(c);
        if (left) {
            c.set_media_start(c.media_start + delta);
        }
        
        c.set_duration(c.length - delta);
        
        shift_clips(index + 1, -delta);
    }
    
    public int64 previous_edit(int64 pos) {
        for (int i = clips.size - 1; i >= 0 ; --i) {
            Clip c = clips[i];
            if (c.start + c.length < pos)
                return c.start + c.length;            
            if (c.start < pos)
                return c.start;
        }
        return 0;
    }

    public int64 next_edit(int64 pos) {
        foreach (Clip c in clips)
            if (c.start > pos)
                return c.start;
        return get_length();
    }

    public virtual void write_attributes(FileStream f) {
        f.printf("type=\"%s\" name=\"%s\" ", name(), get_display_name());
    }
    
    public void save(FileStream f) {
        f.printf("    <track ");
        write_attributes(f);
        f.printf(">\n");
        for (int i = 0; i < clips.size; i++)
            clips[i].save(f, project.get_clipfile_index(clips[i].clipfile));
        f.puts("    </track>\n");
    }
    
    public string get_display_name() {
        return display_name;
    }
    
    public void set_display_name(string new_display_name) {
        if (display_name != new_display_name) {
            display_name = new_display_name;
            track_renamed(this);
        }
    }
    
    public void set_selected(bool is_selected) {
        if (this.is_selected != is_selected) {
            this.is_selected = is_selected;
            track_selection_changed(this);
        }
    }
    
    public bool get_is_selected() {
        return is_selected;
    }
}

public class AudioTrack : Track {
    Gst.Element audio_convert;
    Gst.Element audio_resample;
    Gst.Element level;
    Gst.Element pan;
    Gst.Element volume;

    public signal void parameter_changed(Parameter parameter, double new_value);
    public signal void level_changed(double level_value);
    
    public AudioTrack(Project project, string display_name) {
        base(project, display_name);

        audio_convert = make_element_with_name("audioconvert",
            "audioconvert_%s".printf(display_name));
        audio_resample = make_element_with_name("audioresample",
            "audioresample_%s".printf(display_name));
        level = make_element("level");
 
        pan = make_element("audiopanorama");
        pan.set_property("panorama", 0);
        volume = make_element("volume");
        volume.set_property("volume", 10);

        Value the_level = (uint64) (Gst.SECOND / 30);
        level.set_property("interval", the_level);
        Value true_value = true;
        level.set_property("message", true_value);
        
        if (!project.pipeline.add(audio_convert)) {
            error("could not add audio_convert");
        }
        
        if (!project.pipeline.add(audio_resample)) {
            error("could not add audio_resample");
        }
        
        if (!project.pipeline.add(level)) {
            error("could not add level");
        }
        
        if (!project.pipeline.add(pan)) {
            error("could not add pan");
        }
        
        if (!project.pipeline.add(volume)) {
            error("could not add volume");
        }
        
        project.level_changed += on_level_changed;
    }

    ~AudioTrack() {
        project.pipeline.remove_many(audio_convert, audio_resample, pan, volume);
    }
  
    protected override string name() { return "audio"; }
    
    public override MediaType media_type() {
        return MediaType.AUDIO;
    }

    public override void write_attributes(FileStream f) {
        base.write_attributes(f);
        f.printf("volume=\"%f\" panorama=\"%f\" ", get_volume(), get_pan());
    }

    public void set_pan(double new_value) {
        double old_value = get_pan();
        if (!float_within(new_value - old_value, 0.05)) {
            ParameterCommand parameter_command = 
                new ParameterCommand(this, Parameter.PAN, new_value, old_value);
            project.do_command(parameter_command);
        }
    }
    
    public void _set_pan(double new_value) {
        assert(new_value <= 1.0 && new_value >= -1.0);
        double old_value = get_pan();
        if (!float_within(old_value - new_value, 0.05)) {
            pan.set_property("panorama", new_value);
            parameter_changed(Parameter.PAN, new_value);
        }
    }
    
    public double get_pan() {
        Value the_pan = 0.0;
        pan.get_property("panorama", ref the_pan);
        return the_pan.get_double();
    }
    
    public void set_volume(double new_volume) {
        double old_volume = get_volume();
        if (!float_within(old_volume - new_volume, 0.05)) {
            ParameterCommand parameter_command =
                new ParameterCommand(this, Parameter.VOLUME, new_volume, old_volume);
            project.do_command(parameter_command);
        }
    }

    public void _set_volume(double new_volume) {
        assert(new_volume >= 0.0 && new_volume <= 10.0);
        double old_volume = get_volume();
        if (!float_within(old_volume - new_volume, 0.05)) {
            volume.set_property("volume", new_volume);    
            parameter_changed(Parameter.VOLUME, new_volume);
        }
    }
    
    public double get_volume() {
        Value the_volume = 0.0;
        volume.get_property("volume", ref the_volume);
        return the_volume.get_double();
    }

    protected override Gst.Element empty_element() {
        return project.get_audio_silence();
    }
    
    public override void link_new_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element) {
        if (!bin.link_many(audio_convert, audio_resample, level, pan, volume, track_element)) {
            error("could not link_new_pad for audio track");
        }
    }
    
    public override void unlink_pad(Gst.Bin bin, Gst.Pad pad, Gst.Element track_element) {
        bin.unlink_many(audio_convert, audio_resample, level, pan, volume, track_element);
    }
    
    bool get_num_channels(out int num) {
        for (int i = 0; i < clips.size; i++) {
            if (clips[i].clipfile.is_online())
                return clips[i].clipfile.get_num_channels(out num);
        }
        return false;
    }
    
    public override bool check(Clip clip) {
        if (!clip.clipfile.is_online())
            return true;
        
        if (clips.size == 0) {
            return true;
        }
        
        bool good = false;
        int number_of_channels;
        if (clip.clipfile.get_num_channels(out number_of_channels)) {
            int track_channel_count;
            if (get_num_channels(out track_channel_count)) {
                good = track_channel_count == number_of_channels;
            }
        }
        
        if (!good) {
            string sub_error = number_of_channels == 1 ?
                "Mono clips cannot go on stereo tracks." :
                "Stereo clips cannot go on mono tracks.";
            error_occurred("Cannot add clip to track", sub_error);
        }
        return good;
    }
    
    void on_level_changed(Gst.Object source, double level_value) {
        if (source == level) {
            level_changed(level_value);
        }
    }
}
}
