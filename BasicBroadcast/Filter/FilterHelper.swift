//
// This filter implementation is based on Apple's AVCamFilter implementation
// Please see LICENSE.Apple.txt file for LICENSE information
//

import CoreMedia
import CoreVideo
import CoreImage

class FilterHelper {
    private var videoFilter: ColorFilterRenderer? = ColorFilterRenderer()
    
    private var currentVideoFormat: CMFormatDescription? = nil

    func process(inputBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        // Preparing the final output CMSampleBuffer
        var finalVideoSampleBuffer: CMSampleBuffer?
        
        // obtain pixel buffer and video buffer format
        guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(inputBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(inputBuffer) else {
                print("Unable obtain video buffer format")
                return finalVideoSampleBuffer
        }
        
        // Preparing the final output CVPixelBuffer
        var finalVideoPixelBuffer = videoPixelBuffer
        if let filter = videoFilter {
            // if the resolution changes e.g. video image rotates, the filter's dimention needs to be updated
            if !filter.isPrepared || currentVideoFormat != formatDescription {
                currentVideoFormat = formatDescription
                
                 // outputRetainedBufferCountHint is the number of pixel buffers the filter renderer retains internally.
                 // This value is used to allocated buffer pool within the filter renderer.
                 // The higher number will result in smooth picture quality, however causing delay in frames (5 frame delay by default)
                filter.prepare(with: currentVideoFormat!, outputRetainedBufferCountHint: 5)
            }
            
            // Render the filtered image
            guard let filteredBuffer = filter.render(pixelBuffer: finalVideoPixelBuffer) else {
                print("Unable to apply filter video buffer")
                return finalVideoSampleBuffer
            }
            
            finalVideoPixelBuffer = filteredBuffer
        }
            
        var timimgInfo  = CMSampleTimingInfo()
        var newformatDescription: CMFormatDescription? = nil

        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: finalVideoPixelBuffer, formatDescriptionOut: &newformatDescription)
                    
        CMSampleBufferCreateReadyWithImageBuffer(
              allocator: kCFAllocatorDefault,
              imageBuffer: finalVideoPixelBuffer,
              formatDescription: newformatDescription!,
              sampleTiming: &timimgInfo,
              sampleBufferOut: &finalVideoSampleBuffer
            )
        
        return finalVideoSampleBuffer
    }
}
