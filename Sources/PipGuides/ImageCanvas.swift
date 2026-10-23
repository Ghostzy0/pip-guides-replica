import SwiftUI
import AppKit
import GuidesCore

struct ImageCanvas: View {
    let data: Data
    let click: GuidesCore.UnitPoint?
    @Binding var region: CGRect?
    @Environment(\.guidePalette) private var palette
    var editable: Bool
    @State private var image: NSImage?
    @State private var dragStart: CGPoint?
    var body: some View {
        GeometryReader { geometry in
            let size = image?.size ?? CGSize(width: 1, height: 1)
            let scale = min(geometry.size.width / max(1, size.width), geometry.size.height / max(1, size.height))
            let fitted = CGSize(width: size.width*scale, height: size.height*scale)
            let rect = CGRect(x: (geometry.size.width-fitted.width)/2, y: (geometry.size.height-fitted.height)/2, width: fitted.width, height: fitted.height)
            ZStack(alignment: .topLeading) {
                palette.fill
                if let image { Image(nsImage: image).resizable().interpolation(.high).frame(width: fitted.width, height: fitted.height).position(x: rect.midX, y: rect.midY) }
                else { Text("Picture could not be opened. Replace it to continue.").foregroundStyle(.secondary).padding() }
                if let region {
                    Rectangle().fill(palette.ink.opacity(0.12)).overlay(Rectangle().stroke(palette.ink, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                        .frame(width: region.width*fitted.width, height: region.height*fitted.height)
                        .position(x: rect.minX+region.midX*fitted.width, y: rect.minY+region.midY*fitted.height).allowsHitTesting(false)
                }
                Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 2).onChanged { value in
                    guard editable, image != nil else { return }
                    func clamp(_ p: CGPoint) -> CGPoint { CGPoint(x: min(1,max(0,(p.x-rect.minX)/rect.width)), y: min(1,max(0,(p.y-rect.minY)/rect.height))) }
                    if dragStart == nil { guard rect.contains(value.startLocation) else { return }; dragStart = clamp(value.startLocation) }
                    guard let start = dragStart else { return }; let current = clamp(value.location)
                    region = CGRect(x: min(start.x,current.x), y: min(start.y,current.y), width: abs(start.x-current.x), height: abs(start.y-current.y))
                }.onEnded { _ in dragStart = nil })
            }.clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(palette.line))
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("Step picture. Use Choose centre area and the area fields below to edit without dragging.")
        .onAppear(perform: refresh)
        .onChange(of: data) { refresh() }
        .onChange(of: click) { refresh() }
    }
    private func refresh() { image = (try? ImageTools.marked(data, at: click)).flatMap { NSImage(data: $0) } }
}
