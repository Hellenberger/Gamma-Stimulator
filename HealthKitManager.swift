import HealthKit
import Foundation

class HealthKitManager {
    // Singleton instance
    static let shared = HealthKitManager()
    
    // The HealthKit store
    private let healthStore = HKHealthStore()
    
    // Sleep data types
    private let sleepAnalysisType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    
    // Completion handlers and callback types
    typealias AuthorizationCompletion = (Bool, Error?) -> Void
    typealias SleepDataHandler = ([HKCategorySample]?, Error?) -> Void
    
    private init() {}
    
    // Request authorization to access HealthKit data
    func requestAuthorization(completion: @escaping AuthorizationCompletion) {
        // Define the data types your app needs to read and write
        let typesToRead: Set<HKObjectType> = [
            sleepAnalysisType,
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        
        // Request authorization
        healthStore.requestAuthorization(toShare: nil, read: typesToRead) { (success, error) in
            completion(success, error)
        }
    }
    
    // Check if HealthKit is available on this device
    func isHealthKitAvailable() -> Bool {
        return HKHealthStore.isHealthDataAvailable()
    }
    
    // Get the latest sleep analysis data for a specified time range
    func fetchSleepAnalysisData(from startDate: Date, to endDate: Date, completion: @escaping SleepDataHandler) {
        
        // Create a predicate to filter the data by date
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        // Sort by end date to get the most recent samples first
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        // Create and execute the query
        let query = HKSampleQuery(
            sampleType: sleepAnalysisType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sortDescriptor]
        ) { (_, samples, error) in
            guard let samples = samples as? [HKCategorySample], error == nil else {
                completion(nil, error)
                return
            }
            
            completion(samples, nil)
        }
        
        healthStore.execute(query)
    }
    
    // Get deep sleep (slow wave sleep) episodes from a collection of sleep samples
    func extractDeepSleepEpisodes(from sleepSamples: [HKCategorySample]) -> [HKCategorySample] {
        // Filter for deep sleep (asleepDeep) samples
        return sleepSamples.filter { sample in
            if #available(iOS 16.0, *) {
                // In iOS 16 and later, we can directly check for deep sleep
                return sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue
            } else {
                // For earlier iOS versions, use the asleep value
                // This is less accurate but the best we can do
                return sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue
            }
        }
    }
    
    // Set up a background delivery observer for sleep data
    // Note: This won't deliver real-time sleep stage data, but it can notify
    // when new sleep data is available
    func startSleepAnalysisObserver(updateHandler: @escaping () -> Void) {
        // Create an observer query
        let query = HKObserverQuery(
            sampleType: sleepAnalysisType,
            predicate: nil
        ) { (_, _, error) in
            if error == nil {
                // New data is available, call the update handler
                DispatchQueue.main.async {
                    updateHandler()
                }
            }
        }
        
        // Execute the query and enable background delivery if possible
        healthStore.execute(query)
        
        // Try to enable background delivery
        healthStore.enableBackgroundDelivery(for: sleepAnalysisType, frequency: .immediate) { (success, error) in
            if let error = error {
                print("Failed to enable background delivery: \(error.localizedDescription)")
            }
        }
    }
    
    // Stop observing sleep analysis updates
    func stopSleepAnalysisObserver() {
        healthStore.disableBackgroundDelivery(for: sleepAnalysisType) { (success, error) in
            if let error = error {
                print("Failed to disable background delivery: \(error.localizedDescription)")
            }
        }
    }
}