import Foundation

/// Zero OCR ships as two builds of this code. The Apple silicon edition runs the model on the GPU with
/// Metal and draws everything at full fidelity. The Intel edition is made for 2018 and later Intel Macs
/// with as little as 4 GB of memory: a smaller quantisation on the CPU, smaller images, a model that
/// unloads sooner, and a lighter interface (no web view, no Liquid Glass, the neon at 1x on the
/// integrated GPU).
enum Edition {
    #if arch(x86_64)
    static let intel = true
    #else
    static let intel = false
    #endif

    static var name: String { intel ? "Intel" : "Apple silicon" }

    /// The Intel edition running through Rosetta on an Apple silicon Mac, where it is many times slower.
    static let translated: Bool = {
        var v: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &v, &size, nil, 0) == 0 && v == 1
    }()
}
