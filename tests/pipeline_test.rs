use crossbeam_channel::bounded;
use std::thread;

// Struct shared between your role (#2) and Role #3
#[derive(Debug, PartialEq, Clone)]
pub struct DecodedFrame {
    pub frame_index: u64,
    pub timestamp_ms: i64,
    pub width: u32,
    pub height: u32,
    pub rgb_data: Vec<u8>,
    pub is_keyframe: bool,
}

#[test]
fn test_channel_pipeline_handoff() {
    // 1. Create a bounded channel with capacity for frames
    let (sender, receiver) = bounded::<DecodedFrame>(100);

    // 2. Simulate Role #2 (Your Engine): Producing frames in a thread
    let producer_handle = thread::spawn(move || {
        for i in 0..10 {
            let mock_frame = DecodedFrame {
                frame_index: i,
                timestamp_ms: (i * 33) as i64, // ~30 FPS
                width: 1920,
                height: 1080,
                rgb_data: vec![0u8; 1920 * 1080 * 3], // Dummy RGB buffer
                is_keyframe: i % 5 == 0,
            };
            sender
                .send(mock_frame)
                .expect("Failed to send frame to channel");
        }
    });

    // 3. Simulate Role #3 (Timeline Engineer): Consuming frames from the channel
    let consumer_handle = thread::spawn(move || {
        let mut count = 0;
        while let Ok(frame) = receiver.recv() {
            assert_eq!(frame.width, 1920);
            assert_eq!(frame.height, 1080);
            count += 1;
        }
        count
    });

    producer_handle.join().expect("Producer crashed");
    let total_received = consumer_handle.join().expect("Consumer crashed");

    // Verify all 10 frames were handed off properly without data loss
    assert_eq!(total_received, 10);
}

#[test]
fn test_decoded_frame_ordering_and_pts_continuity() {
    let (sender, receiver) = bounded::<DecodedFrame>(16);

    let frames: Vec<DecodedFrame> = (0..5)
        .map(|i| DecodedFrame {
            frame_index: i,
            timestamp_ms: (i * 40) as i64, // 25 FPS
            width: 1280,
            height: 720,
            rgb_data: vec![128u8; 1280 * 720 * 3],
            is_keyframe: i == 0,
        })
        .collect();

    for f in frames.clone() {
        sender.send(f).unwrap();
    }
    drop(sender);

    let mut prev_ts = -1;
    let mut count = 0;
    while let Ok(frame) = receiver.recv() {
        assert!(frame.timestamp_ms > prev_ts);
        assert_eq!(frame.frame_index, count);
        if count == 0 {
            assert!(frame.is_keyframe);
        }
        prev_ts = frame.timestamp_ms;
        count += 1;
    }
    assert_eq!(count, 5);
}
