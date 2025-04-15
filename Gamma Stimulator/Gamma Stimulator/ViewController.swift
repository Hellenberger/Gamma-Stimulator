import UIKit
import AVFoundation
import Foundation
import AudioToolbox

protocol SynchronizedFlasherDelegate: AnyObject {
    func toggleFlash(on: Bool)
    func onAudioPulse()
}

class ViewController: UIViewController, SynchronizedFlasherDelegate, SleepStimulationControllerDelegate {
    
    // MARK: - Sleep Monitoring Properties
    private let sleepStimulationController = SleepStimulationController()
    private var isSleepMonitoringActive = false
        
    // UI Elements for Sleep Monitoring
    private var sleepStatusLabel: UILabel!
    private var sleepStageLabel: UILabel!
    private var monitoringButton: UIButton!
    
    var audioPlayer: AVAudioPlayer?
    var flashTimer: Timer?
    var isFlashOn = false
    
    var flashCount = 0
    var flashCountTimer: Timer?

    private let flashCountQueue = DispatchQueue(label: "com.yourapp.flashCountQueue")
    
    var countdownTimer: Timer?
    var remainingTime: Int = 0 {
        didSet {
            updateDurationLabel()
        }
    }
    var selectedDuration: TimeInterval = 3000 {
        didSet {
            remainingTime = Int(selectedDuration)
        }
    }
    
    @IBOutlet var mainView: UIView!
    @IBOutlet weak var startStopButton: UIButton!
    @IBOutlet weak var durationLabel: UILabel!
    @IBOutlet weak var durationLabelLeft: UILabel!
    @IBOutlet weak var durationSlider: UISlider!
    @IBOutlet weak var durationSliderLeft: UISlider!
    
    
    lazy var synchronizedFlasher: SynchronizedFlasher? = {
        guard let fileURL = Bundle.main.url(forResource: "pulse", withExtension: "aiff") else {
            print("Failed to find audio file.")
            return nil
        }
        let flasher = SynchronizedFlasher(audioFileURL: fileURL)
        flasher.delegate = self // Make sure the delegate is set right after initialization
        if !flasher.setup() {
            print("Failed to setup the SynchronizedFlasher.")
            return nil
        }
        return flasher
    }()

    lazy var auroraView: AuroraView = {
        let view = AuroraView(frame: self.view.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }()
    
    // Setup UI elements for sleep monitoring
      private func setupSleepMonitoringUI() {
          // Create container view for sleep monitoring controls
          // Create container view for sleep monitoring controls
          let containerView = UIView()
          containerView.backgroundColor = UIColor.black.withAlphaComponent(0.25)
          containerView.layer.cornerRadius = 10
          containerView.translatesAutoresizingMaskIntoConstraints = false
          view.addSubview(containerView)

          // Create sleep status label
          sleepStatusLabel = UILabel()
          sleepStatusLabel.text = "Sleep Monitoring: Inactive"
          sleepStatusLabel.textColor = .white
          sleepStatusLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
          sleepStatusLabel.translatesAutoresizingMaskIntoConstraints = false
          containerView.addSubview(sleepStatusLabel)
          
          // Create sleep stage label
          sleepStageLabel = UILabel()
          sleepStageLabel.text = "Sleep Stage: Unknown"
          sleepStageLabel.textColor = .white
          sleepStageLabel.font = UIFont.systemFont(ofSize: 14)
          sleepStageLabel.translatesAutoresizingMaskIntoConstraints = false
          containerView.addSubview(sleepStageLabel)
          
          // Create monitoring toggle button
          monitoringButton = UIButton(type: .system)
          monitoringButton.setTitle("Start Sleep Monitoring", for: .normal)
          monitoringButton.setTitleColor(.white, for: .normal)
          monitoringButton.backgroundColor = .systemBlue
          monitoringButton.layer.cornerRadius = 8
          monitoringButton.translatesAutoresizingMaskIntoConstraints = false
          monitoringButton.addTarget(self, action: #selector(toggleSleepMonitoring), for: .touchUpInside)
          containerView.addSubview(monitoringButton)
          
          // Layout constraints
          NSLayoutConstraint.activate([
              // Container view
            // Container view - centered with fixed width
                   containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                   containerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
                   containerView.widthAnchor.constraint(equalToConstant: 250), // Fixed width of 250 points
                   
              // Sleep status label
              sleepStatusLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 16),
              sleepStatusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
              sleepStatusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
              
              // Sleep stage label
              sleepStageLabel.topAnchor.constraint(equalTo: sleepStatusLabel.bottomAnchor, constant: 8),
              sleepStageLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
              sleepStageLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
              
              // Monitoring button
              monitoringButton.topAnchor.constraint(equalTo: sleepStageLabel.bottomAnchor, constant: 16),
              monitoringButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
              monitoringButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
              monitoringButton.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -16),
              monitoringButton.heightAnchor.constraint(equalToConstant: 44)
          ])
          
          // Initially hide the container
          containerView.alpha = 0.8
      }
    
    @objc private func toggleSleepMonitoring() {
        if isSleepMonitoringActive {
            // Stop monitoring
            sleepStimulationController.stopMonitoring()
            isSleepMonitoringActive = false
            
            // Update UI
            sleepStatusLabel.text = "Sleep Monitoring: Inactive"
            monitoringButton.setTitle("Start Sleep Monitoring", for: .normal)
            monitoringButton.backgroundColor = .systemBlue
        } else {
            // Start monitoring
            sleepStimulationController.startMonitoring()
            isSleepMonitoringActive = true
            
            // Update UI
            sleepStatusLabel.text = "Sleep Monitoring: Active"
            monitoringButton.setTitle("Stop Sleep Monitoring", for: .normal)
            monitoringButton.backgroundColor = .systemRed
        }
    }
    
    // MARK: - SleepStimulationControllerDelegate
     
    func startStimulation(duration: TimeInterval) {
        DispatchQueue.main.async {
            // Set the timer duration
            self.selectedDuration = duration
            self.remainingTime = Int(duration)
            
            // Start the visual/audio stimulation
            guard let flasher = self.synchronizedFlasher else {
                print("No flasher instance available.")
                return
            }
            
            if !flasher.isRunning {
                flasher.startLoop()
                self.setupCountdownTimer()
                self.startFlashCountTimer()
                
                // Start watch haptic feedback
                PhoneWatchConnector.shared.startWatchHapticFeedback()
            }
        }
    }
     
    func stopStimulation() {
        DispatchQueue.main.async {
            // Stop the stimulation
            guard let flasher = self.synchronizedFlasher else {
                print("No flasher instance available.")
                return
            }
            
            if flasher.isRunning {
                flasher.stopLoop(viewController: self)
                self.stopFlashCountTimer()
                self.countdownTimer?.invalidate()
                self.toggleLEDFlash(on: false)
                
                // Stop watch haptic feedback
                PhoneWatchConnector.shared.stopWatchHapticFeedback()
            }
        }
    }
     
     func didUpdateSleepState(stage: SleepStage, description: String) {
         DispatchQueue.main.async {
             self.sleepStageLabel.text = "Sleep Stage: \(description)"
             
             // Optionally update the UI colors based on sleep stage
             switch stage {
             case .deep:
                 self.sleepStageLabel.textColor = .systemBlue
             case .light:
                 self.sleepStageLabel.textColor = .systemGreen
             case .rem:
                 self.sleepStageLabel.textColor = .systemPurple
             case .awake:
                 self.sleepStageLabel.textColor = .systemOrange
             case .unknown:
                 self.sleepStageLabel.textColor = .white
             }
         }
     }
    
    private func setupTestingControls() {
        let testButton = UIButton(type: .system)
        testButton.setTitle("Run 1-min Test Cycle", for: .normal)
        testButton.backgroundColor = .systemGreen
        testButton.setTitleColor(.white, for: .normal)
        testButton.layer.cornerRadius = 8
        testButton.translatesAutoresizingMaskIntoConstraints = false
        testButton.addTarget(self, action: #selector(runTestCycle), for: .touchUpInside)
        view.addSubview(testButton)
        
        // Position it somewhere visible in your UI
        NSLayoutConstraint.activate([
            testButton.topAnchor.constraint(equalTo: monitoringButton.bottomAnchor, constant: 10),
            testButton.centerXAnchor.constraint(equalTo: monitoringButton.centerXAnchor),
            testButton.widthAnchor.constraint(equalTo: monitoringButton.widthAnchor),
            testButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }

    @objc private func runTestCycle() {
        // Start monitoring if not already active
        if !isSleepMonitoringActive {
            toggleSleepMonitoring()
        }
        
        // Force a test cycle
        sleepStimulationController.runTestCycle()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupSleepMonitoringUI()
        sleepStimulationController.delegate = self
        
        selectedDuration = 3000 // Set your default duration
        remainingTime = Int(selectedDuration) // Initialize remaining time based on the selected duration
        auroraView.setupView() // This encapsulates UI setup including auroraView
        // Update the UI to reflect the initial countdown state
        updateDurationLabel()
        durationLabel.isHidden = false
        durationLabelLeft.isHidden = false
        durationLabel.text = "Time: 50:00"
        durationLabelLeft.text = "Time: 50:00"
        mainView.backgroundColor = .blue
        mainView.isHidden = false
        
        synchronizedFlasher?.delegate = self  // Assign ViewController as the delegate
        
        auroraView = AuroraView(frame: self.view.bounds)
        auroraView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.insertSubview(auroraView, at: 0)
        auroraView.layoutIfNeeded()

    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        updateDurationLabel()
    }
    
    @IBAction func durationSliderChanged(_ sender: UISlider) {
        selectedDuration = Double(sender.value) * 3000 // Assuming slider value represents seconds
        remainingTime = Int(selectedDuration)
        durationSlider.value = sender.value
        durationSliderLeft.value = sender.value
        updateDurationLabel()
    }

    @IBAction func startStop(_ sender: UIButton) {
        guard let flasher = synchronizedFlasher else {
            print("No flasher instance available.")
            return
        }

        if !flasher.isRunning {
            flasher.startLoop()
            setupCountdownTimer()
            startFlashCountTimer()  // Start the flash count timer only when starting flashes.
        } else {
            flasher.stopLoop(viewController: self)
            stopFlashCountTimer()  // Stop counting flashes when the loop stops.
            countdownTimer?.invalidate()  // Optionally stop other related timers.
            toggleLEDFlash(on: false)  // Ensure LED is off
        }
    }

    func onAudioPulse() {
        DispatchQueue.main.async {  // Ensure UI updates are on the main thread
            self.toggleFlash()
            self.toggleLEDFlash(on: self.isFlashOn, level: Float(UIScreen.main.brightness))  // Add this line to control the LED torch
            self.flashCount += 1  // Only increment the flash count here.
        }
    }

    func toggleLEDFlash(on: Bool, level: Float = 1.0) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            print("Torch not available")
            return
        }

        do {
            try device.lockForConfiguration()
            if on && level > 0 {
                try device.setTorchModeOn(level: level)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            print("Torch could not be used: \(error)")
        }
    }
    
    // This method directly handles the visual effect toggle, called from wherever needed.
    func toggleFlash() {
        isFlashOn.toggle()
        auroraView.alpha = isFlashOn ? 1 : 0
        //print("Flash toggled to \(isFlashOn ? "ON" : "OFF") at \(Date()) - Total flashes: \(flashCount)")
    }
    
    func toggleFlash(on: Bool) {
        DispatchQueue.main.async {
            //print("Flash toggled \(on ? "ON" : "OFF")")
            self.auroraView.alpha = on ? 1.0 : 0.0
        }
    }
    
    func startFlashCountTimer() {
        flashTimer?.invalidate()  // Invalidate any existing timer to prevent multiple timers running.
        flashCount = 0  // Reset the count when starting new.
        flashTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            print("Flashes this second: \(self.flashCount)")
            self.flashCount = 0  // Reset the count after logging.
        }
        RunLoop.main.add(flashTimer!, forMode: .common)
    }

    func stopFlashCountTimer() {
        flashTimer?.invalidate()  // Stop the timer
        flashTimer = nil
        print("Flash count timer stopped.")
    }
    
    func didFailToStartPlayback(error: Error) {
        // Handle playback error (e.g., show an alert)
        print("Playback error: \(error.localizedDescription)")
    }
    
    func setupCountdownTimer() {
        // Setup and start the countdown timer based on the remainingTime
        countdownTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(updateCountdown), userInfo: nil, repeats: true)
    }
    
    @objc func updateCountdown() {
        if remainingTime > 0 {
            remainingTime -= 1
            updateDurationLabel()
        } else {
            countdownTimer?.invalidate()
            // Handle what happens when the timer reaches 0
        }
    }
    
    func updateDurationLabel() {
        
        
        guard isViewLoaded && view.window != nil else { return }
        
        let minutes = remainingTime / 60
        let seconds = remainingTime % 60
        let timeString = String(format: "Time: %02d:%02d", minutes, seconds)
        durationLabel.text = timeString
        durationLabelLeft.text = timeString
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
            
        // Stop sleep monitoring if active
        if isSleepMonitoringActive {
            sleepStimulationController.stopMonitoring()
            isSleepMonitoringActive = false
        }
    
    }


class SynchronizedFlasher {
    weak var delegate: SynchronizedFlasherDelegate?
    var audioFile: AudioFileID?
    var localFormat: AudioStreamBasicDescription?
    var isRunning = false
    var currentPacketOffset: Int64 = 0
    var totalPacketsInFile: Int64 = 0
    
    var maxPacketSize: UInt32 = 0     // Store max packet size as a property
    var expectedFlashCount = 0
    var loopTimer: Timer?
    
    private let audioFileURL: URL
    private var isReadyToPlay = false
    private var buffers: [AudioQueueBufferRef] = []
    private var currentBufferIndex: Int = 0
    private var audioFormat: AudioStreamBasicDescription?
    var audioQueue: AudioQueueRef? = nil
    let vc = ViewController()
    
    init(audioFileURL: URL) {
        self.audioFileURL = audioFileURL
    }
    
    static let audioQueueOutputCallback: AudioQueueOutputCallback = { userData, queue, buffer in

        guard let userData = userData else {
            print("UserData is nil")
            return
        }

        let flasher = Unmanaged<SynchronizedFlasher>.fromOpaque(userData).takeUnretainedValue()
        flasher.delegate?.onAudioPulse()
        // Ensure buffer is re-enqueued
        let enqueueResult = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
        if enqueueResult != noErr {
            print("Failed to re-enqueue buffer: \(enqueueResult)")
        }
    }


    func fourCharString(from code: UInt32) -> String {
        guard code > 0 else { return "Invalid Code" }
        let characters = [
            Character(UnicodeScalar((code >> 24) & 255)!),
            Character(UnicodeScalar((code >> 16) & 255)!),
            Character(UnicodeScalar((code >> 8) & 255)!),
            Character(UnicodeScalar(code & 255)!)
        ]
        return String(characters)
    }
    
    func setup() -> Bool {
        if !setupAudioSession() {
            return false
        }
        return setupAudioComponents()
    }
    
    struct AudioFileInfo {
        var audioFile: AudioFileID
        var localFormat: AudioStreamBasicDescription
        var totalPackets: UInt64
        var maxPacketSize: UInt32
    }
    
    // Helper function to determine file size
    private func fileSize(for audioFileID: AudioFileID) -> UInt64 {
        var propertySize = UInt32(MemoryLayout<size_t>.size)
        var fileSize: UInt64 = 0
        let status = AudioFileGetProperty(audioFileID, kAudioFilePropertyAudioDataByteCount, &propertySize, &fileSize)
        if status != noErr {
            print("Error retrieving file size: \(status)")
            return 0
        }
        return fileSize
    }
    
    private func setupAudioSession() -> Bool {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("Audio session setup successfully.")
            return true
        } catch {
            print("Failed to set up and activate audio session: \(error.localizedDescription)")
            return false
        }
    }
    
    func setupAudioComponents() -> Bool {
        print("Setting up audio components.")
        guard let setupInfo = openAndSetupAudioFile() else {
            print("Failed to setup audio components properly.")
            return false
        }

        // Setup properties from file info
        self.audioFile = setupInfo.audioFile
        self.localFormat = setupInfo.localFormat
        self.totalPacketsInFile = Int64(setupInfo.totalPackets)
        self.maxPacketSize = setupInfo.maxPacketSize

        // Setup buffer size based on total packets and max packet size
        let bufferSize = calculateBufferSize(format: self.localFormat!, maxPacketSize: self.maxPacketSize, totalPackets: UInt64(self.totalPacketsInFile))

        if setupAudioQueue() {
            print("Audio queue setup successfully.")
            setupBuffers(bufferSize: bufferSize)
            return true
        } else {
            print("Failed to setup audio queue.")
            return false
        }
    }

    func openAndSetupAudioFile() -> AudioFileInfo? {
        var audioFileID: AudioFileID?
        let status = AudioFileOpenURL(audioFileURL as CFURL, .readPermission, 0, &audioFileID)
        if status != noErr {
            print("Failed to open audio file with error code: \(status)")
            return nil
        }

        guard let file = audioFileID else {
            print("Audio file ID is nil after opening.")
            return nil
        }

        var fileTypeSpec = AudioStreamBasicDescription()
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let formatStatus = AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &propertySize, &fileTypeSpec)
        if formatStatus != noErr {
            print("Failed to read audio format from file: \(formatStatus)")
            AudioFileClose(file)
            return nil
        }

        var packetCount: UInt64 = 0
        propertySize = UInt32(MemoryLayout<UInt64>.size)  // Correctly setting dataSize for packet count retrieval
        var propStatus = AudioFileGetProperty(file, kAudioFilePropertyAudioDataPacketCount, &propertySize, &packetCount)
        if propStatus != noErr {
            print("Failed to retrieve packet count: \(propStatus)")
            AudioFileClose(file)
            return nil
        }

        var maxPacketSize: UInt32 = 0
        propertySize = UInt32(MemoryLayout<UInt32>.size)  // Correctly setting dataSize for maximum packet size retrieval
        propStatus = AudioFileGetProperty(file, kAudioFilePropertyMaximumPacketSize, &propertySize, &maxPacketSize)
        if propStatus != noErr {
            print("Failed to retrieve max packet size: \(propStatus)")
            AudioFileClose(file)
            return nil
        }
        print("""
            Audio File Format Details:
            - Sample Rate: \(fileTypeSpec.mSampleRate) Hz
            - Format Flags: \(fileTypeSpec.mFormatFlags)
            - Bytes Per Packet: \(fileTypeSpec.mBytesPerPacket)
            - Frames Per Packet: \(fileTypeSpec.mFramesPerPacket)
            - Bytes Per Frame: \(fileTypeSpec.mBytesPerFrame)
            - Channels Per Frame: \(fileTypeSpec.mChannelsPerFrame)
            - Bits Per Channel: \(fileTypeSpec.mBitsPerChannel)
            - Total Packets: \(packetCount)
            - Maximum Packet Size: \(maxPacketSize)
        """)
        
        print("""
            Detailed Audio File Format:
            - Sample Rate: \(fileTypeSpec.mSampleRate) Hz
            - Format Flags: \(fileTypeSpec.mFormatFlags)
            - Bytes Per Packet: \(fileTypeSpec.mBytesPerPacket)
            - Frames Per Packet: \(fileTypeSpec.mFramesPerPacket)
            - Bytes Per Frame: \(fileTypeSpec.mBytesPerFrame)
            - Channels Per Frame: \(fileTypeSpec.mChannelsPerFrame)
            - Bits Per Channel: \(fileTypeSpec.mBitsPerChannel)
        """)


        return AudioFileInfo(audioFile: file, localFormat: fileTypeSpec, totalPackets: packetCount, maxPacketSize: maxPacketSize)
    }
    func checkAudioFileProperties(_ audioFile: AudioFileID) {
        var fileSize: UInt64 = 0
        var propertySize: UInt32 = UInt32(MemoryLayout.size(ofValue: fileSize))
        let status = AudioFileGetProperty(audioFile, kAudioFilePropertyAudioDataByteCount, &propertySize, &fileSize)
        
        if status == noErr {
            print("Total audio data size: \(fileSize) bytes")
        } else {
            print("Failed to get audio file size, error code: \(status)")
        }
        
        // Fetching and logging other relevant properties might help diagnose issues
        var format: AudioStreamBasicDescription = AudioStreamBasicDescription()
        propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let formatStatus = AudioFileGetProperty(audioFile, kAudioFilePropertyDataFormat, &propertySize, &format)
        
        if formatStatus == noErr {
            print("Audio Format: \(format)")
        } else {
            print("Failed to get audio format, error code: \(formatStatus)")
        }
    }

   
    func logAudioFileProperties() {
        guard let audioFile = audioFile else { return }
        var size: UInt64 = 0
        var sizePropertySize: UInt32 = UInt32(MemoryLayout.size(ofValue: size))
        AudioFileGetProperty(audioFile, kAudioFilePropertyAudioDataByteCount, &sizePropertySize, &size)
        print("Audio file size: \(size) bytes")
    }
    
    deinit {
        if let audioFile = audioFile {
            AudioFileClose(audioFile)
            print("Audio file closed successfully.")
            loopTimer?.invalidate()
            vc.flashCountTimer?.invalidate()
        }
    }
    
    public func setupAudioQueue() -> Bool {
        if self.audioQueue != nil {
            print("Audio queue already exists, no need to recreate.")
            return true
        }

        guard var format = self.localFormat else {
            print("Audio format is nil, cannot create audio queue")
            return false
        }

        var queue: AudioQueueRef?
        let status = AudioQueueNewOutput(&format, SynchronizedFlasher.audioQueueOutputCallback, Unmanaged.passUnretained(self).toOpaque(), nil, nil, 0, &queue)

        if status != noErr {
            print("Error creating audio queue: \(status)")
            return false
        }

        self.audioQueue = queue
        print("Audio queue successfully created with format: \(format.mSampleRate) Hz, \(format.mChannelsPerFrame) channel(s), \(format.mBitsPerChannel) bit.")
        return true
    }
    
    func readAudioPackets(audioFile: AudioFileID, startPacketIndex: UInt32, numPacketsToRead: UInt32, buffer: AudioQueueBufferRef) {
        
        //var numBytesRead: UInt32 = 0
        var numBytesRead: UInt32 = buffer.pointee.mAudioDataByteSize

        var numPacketsToReadMutable = numPacketsToRead
        let byteOffset = UInt64(startPacketIndex) * UInt64(maxPacketSize)
        let packetDataPointer = buffer.pointee.mAudioData.assumingMemoryBound(to: UInt8.self)

        print("Reading audio packets with byteOffset: \(byteOffset), numPacketsToRead: \(numPacketsToReadMutable)")

        let readStatus = AudioFileReadPacketData(
            audioFile,
            false,
            &numBytesRead,
            nil,
            Int64(byteOffset),
            &numPacketsToReadMutable,
            packetDataPointer
        )
        print("Attempting to read audio packets with the following parameters:")
        print("Start Packet Index: \(startPacketIndex)")
        print("Number of Packets to Read: \(numPacketsToRead)")
        print("Buffer Byte Size: \(buffer.pointee.mAudioDataByteSize)")
        print("Byte Offset: \(byteOffset)")

        if readStatus == noErr {
            buffer.pointee.mAudioDataByteSize = numBytesRead
            print("Successfully read \(numBytesRead) bytes from the audio file.")
        } else {
            print("Failed to read audio data: \(readStatus) - \(fourCharString(from: UInt32(bitPattern: Int32(readStatus)))). Expected to read \(numPacketsToRead) packets but only read \(numBytesRead) bytes.")
        }
    }
    
    func calculateBufferSize(format: AudioStreamBasicDescription, maxPacketSize: UInt32, totalPackets: UInt64) -> UInt32 {
        return UInt32(totalPackets) * maxPacketSize  // Calculates the exact buffer size needed
    }

    func setupBuffers(bufferSize: UInt32) {
        guard let audioQueue = self.audioQueue else {
            print("Audio queue not set up.")
            return
        }

        for _ in 0..<3 {  // Assuming 3 buffers are needed
            var buffer: AudioQueueBufferRef?
            let status = AudioQueueAllocateBuffer(audioQueue, bufferSize, &buffer)
            if status == noErr, let buffer = buffer {
                buffer.pointee.mAudioDataByteSize = bufferSize  // Correctly initialize the byte size
                readAudioPackets(audioFile: self.audioFile!, startPacketIndex: 0, numPacketsToRead: UInt32(self.totalPacketsInFile), buffer: buffer)
                AudioQueueEnqueueBuffer(audioQueue, buffer, 0, nil)
                print("Buffer enqueued, size \(bufferSize).")
            } else {
                print("Error allocating buffer: \(status)")
            }
        }
    }

    func fillBuffer(_ buffer: AudioQueueBufferRef, bufferSize: UInt32, numPacketsToRead: UInt32) {
        guard let audioFile = self.audioFile else {
            print("Audio file is nil")
            return
        }

        var numBytesRead: UInt32 = buffer.pointee.mAudioDataByteSize

        var packetsToRead = numPacketsToRead  // Declare as var to pass as inout
        let packetDataPointer = buffer.pointee.mAudioData.assumingMemoryBound(to: UInt8.self)

        print("Attempting to read \(packetsToRead) packets from the audio file.")

        let readStatus = AudioFileReadPacketData(
            audioFile,
            false,
            &numBytesRead,
            nil,
            0,  // start reading from the beginning
            &packetsToRead,  // Now passing as inout, which is mutable
            packetDataPointer
        )

        if readStatus == noErr {
            buffer.pointee.mAudioDataByteSize = numBytesRead
            print("Successfully read \(numBytesRead) bytes from the audio file, covering \(packetsToRead) packets.")
        } else {
            print("Failed to read audio data: \(readStatus). Expected to read \(packetsToRead) packets but only read \(numBytesRead) bytes.")
        }
    }

    func detectPulse(in data: UnsafeMutableRawPointer, size: UInt32) -> Bool {
        // Implement pulse detection logic based on the audio data characteristics
        // Placeholder: simple threshold-based detection
        let threshold: Int16 = 90  // Define a suitable threshold based on the audio data
        let sampleBuffer = data.assumingMemoryBound(to: Int16.self)
        for i in 0..<Int(size) / MemoryLayout<Int16>.size {
            if abs(sampleBuffer[i]) > threshold {
                return true
            }
        }
        return false
    }
    
    func startAudioQueue() {
        guard let audioQueue = self.audioQueue else {
            print("Audio queue is not initialized.")
            return
        }

        if !isRunning {
            let status = AudioQueueStart(audioQueue, nil)
            if status == noErr {
                isRunning = true
                print("Audio queue started successfully.")
            } else {
                let errorString = fourCharString(from: UInt32(status))
                print("Failed to start audio queue: \(status) - \(errorString)")
            }
        } else {
            print("Audio queue is already running.")
        }
    }
    
    func startLoop() {
        if !isRunning {
            if setupAudioQueue() {
                let bufferSize = calculateBufferSize(format: localFormat!, maxPacketSize: maxPacketSize, totalPackets: UInt64(totalPacketsInFile))
                setupBuffers(bufferSize: bufferSize)
                startAudioQueue()
                isRunning = true
            } else {
                print("Failed to setup audio queue.")
            }
        }
    }

     func scheduleFlashCountIncrement() {
         // Cancel previous timer if it exists
         loopTimer?.invalidate()
         
         // Create a new timer that increments the expectedFlashCount
         let loopInterval = calculateLoopDuration()
         loopTimer = Timer.scheduledTimer(withTimeInterval: loopInterval, repeats: true) { [weak self] _ in
             guard let self = self else { return }
             self.expectedFlashCount += 1
             print("Expected flash count incremented to: \(self.expectedFlashCount)")
         }
         RunLoop.main.add(loopTimer!, forMode: .common)
     }

     func calculateLoopDuration() -> TimeInterval {
         // Assuming the loop duration is determined based on the audio format
         let sampleRate = Double(localFormat?.mSampleRate ?? 44100)
         let totalFrames = Double(totalPacketsInFile)
         return totalFrames / sampleRate
     }

    func stopLoop(viewController: UIViewController) {
        if isRunning {
            AudioQueueStop(audioQueue!, true)
            isRunning = false
            print("Audio queue stopped.")
        }
    }

    
    // Update UI
    func updatePlaybackUI(viewController: ViewController) {

      // Unwrap timer
      if let timer = vc.countdownTimer {

        // Calculate time
        let fireDate = timer.fireDate
        let now = Date()
        let timeRemaining = fireDate.timeIntervalSince(now)

        // Update duration label
        let minutes = Int(timeRemaining) / 60
        let seconds = Int(timeRemaining) % 60
        vc.durationLabel.text = "\(minutes):\(seconds)"

      }
    }
}
    
protocol AuroraViewDelegate: AnyObject {
    func toggleLEDFlash(on: Bool, level: Float)
}

class AuroraView: UIView {
    
    weak var delegate: AuroraViewDelegate?
    
    var flashTimer: Timer?
    var isFlashOn = false
    var isFlashing = false
    private let gradientImageLayer = CALayer()
    private let replicatorLayer = CAReplicatorLayer()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    let dimView = UIView(frame: UIScreen.main.bounds)
    
    @objc func handlePanGesture(_ recognizer: UIPanGestureRecognizer) {
        let velocity = recognizer.velocity(in: dimView)
        let verticalVelocity = abs(velocity.y)
        let scaledBrightnessChange = verticalVelocity / (dimView.bounds.height * 15) // Adjust divisor as needed

        if velocity.y > 0 {
            // Decrease screen brightness when panning down
            UIScreen.main.brightness = max(0, UIScreen.main.brightness - scaledBrightnessChange)
        } else {
            // Increase screen brightness when panning up
            UIScreen.main.brightness = min(1, UIScreen.main.brightness + scaledBrightnessChange)
        }

        // Adjust LED brightness
        let newTorchLevel = Float(UIScreen.main.brightness)
        delegate?.toggleLEDFlash(on: newTorchLevel > 0, level: newTorchLevel)
    }
    
    func setupView() {
        // Make sure background color is clear to allow gradient visibility
        self.backgroundColor = .clear
        let mmPerInch: CGFloat = 25.4
        let pointsPerInch: CGFloat = 160
        let desiredDistanceInMM: CGFloat = 62
        let desiredDistanceInPoints = (desiredDistanceInMM / mmPerInch) * pointsPerInch
        if let gradientImage = createRadialGradientImage(in: CGRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height), colors: [.black, .darkGray, .gray, .lightGray, .white, .yellow, .green, .red, .blue], locations: [0.0, 0.0010, 0.0015, 0.005, 0.030, 0.10 , 0.25, 0.5, 0.75]) {
            gradientImageLayer.contents = gradientImage.cgImage
            gradientImageLayer.frame = CGRect(x: desiredDistanceInPoints / 2, y: 0, width: bounds.width / 2, height: bounds.height)
            gradientImageLayer.opacity = 1.0
        }

        replicatorLayer.instanceCount = 2
        replicatorLayer.instanceTransform = CATransform3DMakeTranslation(desiredDistanceInPoints, 0, 0)
        layer.addSublayer(replicatorLayer)
        replicatorLayer.addSublayer(gradientImageLayer)
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        dimView.addGestureRecognizer(panGesture)
        self.addSubview(dimView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let mmPerInch: CGFloat = 25.4
        let pointsPerInch: CGFloat = 160
        let desiredDistanceInMM: CGFloat = 62
        let desiredDistanceInPoints = (desiredDistanceInMM / mmPerInch) * pointsPerInch
        gradientImageLayer.frame = CGRect(x: desiredDistanceInPoints / 2, y: 0, width: bounds.width / 2, height: bounds.height)
        replicatorLayer.frame = bounds
        replicatorLayer.instanceTransform = CATransform3DMakeTranslation(desiredDistanceInPoints, 0, 0)
        let shiftDistanceInMM: CGFloat = 5
        let shiftDistanceInPoints = (shiftDistanceInMM / mmPerInch) * pointsPerInch
        replicatorLayer.position.x = bounds.midX - desiredDistanceInPoints / 2 + shiftDistanceInPoints
    }


    
    func createRadialGradientImage(in frame: CGRect, colors: [UIColor], locations: [CGFloat]) -> UIImage? {
        let startPoint = CGPoint(x: frame.midX, y: frame.midY)
        let endPoint = startPoint
        let startRadius: CGFloat = 0
        let endRadius = max(frame.width, frame.height) / 2
        
        UIGraphicsBeginImageContextWithOptions(frame.size, false, 0)
        guard let context = UIGraphicsGetCurrentContext(),
              let gradient = CGGradient(colorsSpace: nil, colors: colors.map { $0.cgColor } as CFArray, locations: locations) else {
            UIGraphicsEndImageContext()
            return nil
        }
        
        context.drawRadialGradient(gradient, startCenter: startPoint, startRadius: startRadius, endCenter: endPoint, endRadius: endRadius, options: [])
        
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return image
    }
    
    func stopFlashing() {
        isFlashing = false
        
        self.isHidden = true
    }
        
    }
}
