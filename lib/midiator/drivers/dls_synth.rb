# A MIDI driver to play MIDI using OSX's built in DLS synthesizer.
#
# == Authors
#
# * Adam Murray <adam@compusition.com>
#
# == Contributors
#
# * Jeremy Voorhis <jvoorhis@gmail.com>
#
# == Copyright
#
# Copyright (c) 2008 Adam Murray
#
# This code released under the terms of the MIT license.
#

require 'rubygems'
require 'ffi'

class String
  def to_bytes
    bytes = 0
    self.each_byte do |byte|
      bytes <<= 8
      bytes += byte
    end
    return bytes
  end
end

class MIDIator::Driver::DLSSynth < MIDIator::Driver # :nodoc:
  
  attr_accessor :synth

  module AudioToolbox
    extend FFI::Library
    ffi_lib '/System/Library/Frameworks/AudioToolbox.framework/Versions/Current/AudioToolbox'

    class ComponentDescription < FFI::Struct
      layout :componentType,         :int,
             :componentSubType,      :int,
             :componentManufacturer, :int,
             :componentFlags,        :int,
             :componentFlagsMask,    :int
    end
    
    # to_bytes may not be strictly necessary but these are supposed to be 4 byte numbers
    AudioUnitManufacturer_Apple    = 'appl'.to_bytes
    AudioUnitType_MusicDevice      = 'aumu'.to_bytes
    AudioUnitSubType_DLSSynth      = 'dls '.to_bytes
    AudioUnitType_Output           = 'auou'.to_bytes
    AudioUnitSubType_DefaultOutput = 'def '.to_bytes
    
    attach_function :NewAUGraph, [:pointer], :int
    attach_function :AUGraphAddNode, [:pointer, :pointer, :pointer], :int
    attach_function :AUGraphOpen, [:pointer], :int
    attach_function :AUGraphConnectNodeInput, [:pointer, :pointer, :int, :pointer, :int], :int
    attach_function :AUGraphNodeInfo, [:pointer, :pointer, :pointer, :pointer], :int
    attach_function :AUGraphInitialize, [:pointer], :int
    attach_function :AUGraphStart, [:pointer], :int
    attach_function :AUGraphStop, [:pointer], :int
    attach_function :DisposeAUGraph, [:pointer], :int
    
    attach_function :CAShow, [:pointer], :pointer

    attach_function :MusicDeviceMIDIEvent, [:pointer, :int, :int, :int, :int], :pointer
  end      

  protected

  def require_noerr(action_description, &block)
    if block.call != 0
      fail "Failed to #{action_description}"
    end
  end

  def open
    cd = AudioToolbox::ComponentDescription.new(FFI::MemoryPointer.new(AudioToolbox::ComponentDescription.size))
    cd[:componentManufacturer] = AudioToolbox::AudioUnitManufacturer_Apple
    cd[:componentFlags] = 0
    cd[:componentFlagsMask] = 0

    graph_ptr = FFI::MemoryPointer.new(:pointer)
    require_noerr('create AUGraph') { AudioToolbox.NewAUGraph(graph_ptr) }
    @graph = graph_ptr.read_pointer

    cd[:componentType] = AudioToolbox::AudioUnitType_MusicDevice
    cd[:componentSubType] = AudioToolbox::AudioUnitSubType_DLSSynth
    synth_node_ptr = FFI::MemoryPointer.new(:pointer)
    require_noerr('add synthNode') { AudioToolbox.AUGraphAddNode(@graph, cd, synth_node_ptr) }
    synth_node = synth_node_ptr.read_pointer

    cd[:componentType] = AudioToolbox::AudioUnitType_Output
    cd[:componentSubType] = AudioToolbox::AudioUnitSubType_DefaultOutput
    
    out_node_ptr = FFI::MemoryPointer.new(:pointer)
    require_noerr('add out_node') { AudioToolbox.AUGraphAddNode(@graph, cd, out_node_ptr) }
    out_node = out_node_ptr.read_pointer

    require_noerr('open graph') { AudioToolbox.AUGraphOpen(@graph) }

    require_noerr('connect synth to out') { AudioToolbox.AUGraphConnectNodeInput(@graph, synth_node, 0, out_node, 0) }

    synth_ptr = FFI::MemoryPointer.new(:pointer)
    require_noerr('graph info') { AudioToolbox.AUGraphNodeInfo(@graph, synth_node, nil, synth_ptr) }
    @synth = synth_ptr.read_pointer
    require_noerr('init graph') { AudioToolbox.AUGraphInitialize(@graph) }
    require_noerr('start graph') { AudioToolbox.AUGraphStart(@graph) }

    AudioToolbox.CAShow(@graph) if $DEBUG
  end

  def message(*args)
    arg0 = args[0] || 0
    arg1 = args[1] || 0
    arg2 = args[2] || 0
    AudioToolbox.MusicDeviceMIDIEvent(@synth, arg0, arg1, arg2, 0)
  end

  def close
    if @graph
      AudioToolbox.AUGraphStop(@graph)
      AudioToolbox.DisposeAUGraph(@graph)
    end
  end
end
