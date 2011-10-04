///
//  RMPath.m
//
// Copyright (c) 2008-2009, Route-Me Contributors
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice, this
//   list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

#import "RMPath.h"
#import "RMMapView.h"
#import "RMMapContents.h"
#import "RMMercatorToScreenProjection.h"
#import "RMPixel.h"
#import "RMProjection.h"

@implementation RMPath

@synthesize scaleLineWidth;
@synthesize projectedLocation;
@synthesize enableDragging;
@synthesize enableRotation;
@synthesize lineDashPhase;
@synthesize scaleLineDash;

#define kDefaultLineWidth 2

- (id) initWithContents: (RMMapContents*)aContents
{
	if (![super init])
		return nil;
	
	mapContents = aContents;

	path = CGPathCreateMutable();
	
	lineWidth = kDefaultLineWidth;
	drawingMode = kCGPathFillStroke;
	lineCap = kCGLineCapButt;
	lineJoin = kCGLineJoinMiter;
	lineColor = [UIColor blackColor];
	fillColor = [UIColor redColor];
	_lineDashCount = 0;
    _lineDashLengths = NULL;
    _scaledLineDashLengths = NULL;
    lineDashPhase = 0.0;
    
	self.masksToBounds = YES;
	
	scaleLineWidth = NO;
    scaleLineDash = NO;
	enableDragging = YES;
	enableRotation = YES;
	isFirstPoint = YES;
	
    if ( [self respondsToSelector:@selector(setContentsScale:)] )
    {
        [(id)self setValue:[[UIScreen mainScreen] valueForKey:@"scale"] forKey:@"contentsScale"];
    }
	
	return self;
}

- (id) initForMap: (RMMapView*)map
{
	return [self initWithContents:[map contents]];
}

-(void) dealloc
{
	CGPathRelease(path);
    [self setLineColor:nil];
    [self setFillColor:nil];
	
	[super dealloc];
}

- (id<CAAction>)actionForKey:(NSString *)key
{
	return nil;
}

- (void) recalculateGeometry
{
	RMMercatorToScreenProjection *projection = [mapContents mercatorToScreenProjection];
	float scale = [projection metersPerPixel];
	float scaledLineWidth;
	CGPoint myPosition;
	CGRect pixelBounds, screenBounds;
	float offset;
	const float outset = 100.0f; // provides a buffer off screen edges for when path is scaled or moved
	
	// The bounds are actually in mercators...
	/// \bug if "bounds are actually in mercators", shouldn't be using a CGRect
	scaledLineWidth = lineWidth;
	if(!scaleLineWidth) {
		renderedScale = [mapContents metersPerPixel];
		scaledLineWidth *= renderedScale;
	}
	
	CGRect boundsInMercators = CGPathGetBoundingBox(path);
	boundsInMercators = CGRectInset(boundsInMercators, -scaledLineWidth, -scaledLineWidth);
	
	// Increase the size of the bounds by twice the tapping threshold to allow
	// for taps on points that lie near the edges of the layer
	pixelBounds = CGRectInset(boundsInMercators, -scaledLineWidth - (kDefaultTapThresholdDistance * 2), -scaledLineWidth - (kDefaultTapThresholdDistance * 2));
	
	pixelBounds = RMScaleCGRectAboutPoint(pixelBounds, 1.0f / scale, CGPointZero);
	
	// Clip bound rect to screen bounds.
	// If bounds are not clipped, they won't display when you zoom in too much.
	myPosition = [projection projectXYPoint: projectedLocation];
	screenBounds = [mapContents screenBounds];
	
	// Clip top
	offset = myPosition.y + pixelBounds.origin.y - screenBounds.origin.y + outset;
	if(offset < 0.0f) {
		pixelBounds.origin.y -= offset;
		pixelBounds.size.height += offset;
	}
	// Clip left
	offset = myPosition.x + pixelBounds.origin.x - screenBounds.origin.x + outset;
	if(offset < 0.0f) {
		pixelBounds.origin.x -= offset;
		pixelBounds.size.width += offset;
	}
	// Clip bottom
	offset = myPosition.y + pixelBounds.origin.y + pixelBounds.size.height - screenBounds.origin.y - screenBounds.size.height - outset;
	if(offset > 0.0f) {
		pixelBounds.size.height -= offset;
	}
	// Clip right
	offset = myPosition.x + pixelBounds.origin.x + pixelBounds.size.width - screenBounds.origin.x - screenBounds.size.width - outset;
	if(offset > 0.0f) {
		pixelBounds.size.width -= offset;
	}
	
	[super setPosition:myPosition];
	self.bounds = pixelBounds;
	//RMLog(@"x:%f y:%f screen bounds: %f %f %f %f", myPosition.x, myPosition.y,  screenBounds.origin.x, screenBounds.origin.y, screenBounds.size.width, screenBounds.size.height);
	//RMLog(@"new bounds: %f %f %f %f", self.bounds.origin.x, self.bounds.origin.y, self.bounds.size.width, self.bounds.size.height);
	
	self.anchorPoint = CGPointMake(-pixelBounds.origin.x / pixelBounds.size.width,-pixelBounds.origin.y / pixelBounds.size.height);
	[self setNeedsDisplay];
}

- (void) addPointToXY: (RMProjectedPoint) point withDrawing: (BOOL)isDrawing
{
	//	RMLog(@"addLineToXY %f %f", point.x, point.y);


	if(isFirstPoint)
	{
		isFirstPoint = FALSE;
		projectedLocation = point;

		self.position = [[mapContents mercatorToScreenProjection] projectXYPoint: projectedLocation];
		//		RMLog(@"screen position set to %f %f", self.position.x, self.position.y);
		CGPathMoveToPoint(path, NULL, 0.0f, 0.0f);
	}
	else
	{
		point.easting = point.easting - projectedLocation.easting;
		point.northing = point.northing - projectedLocation.northing;

		if (isDrawing)
		{
			CGPathAddLineToPoint(path, NULL, point.easting, -point.northing);
		} else {
			CGPathMoveToPoint(path, NULL, point.easting, -point.northing);
		}

		[self recalculateGeometry];
	}
	[self setNeedsDisplay];
}

- (void) moveToXY: (RMProjectedPoint) point
{
	[self addPointToXY: point withDrawing: FALSE];
}

- (void) moveToScreenPoint: (CGPoint) point
{
	RMProjectedPoint mercator = [[mapContents mercatorToScreenProjection] projectScreenPointToXY: point];
	
	[self moveToXY: mercator];
}

- (void) moveToLatLong: (RMLatLong) point
{
	RMProjectedPoint mercator = [[mapContents projection] latLongToPoint:point];
	
	[self moveToXY:mercator];
}

- (void) addLineToXY: (RMProjectedPoint) point
{
	[self addPointToXY: point withDrawing: TRUE];
}

- (void) addLineToScreenPoint: (CGPoint) point
{
	RMProjectedPoint mercator = [[mapContents mercatorToScreenProjection] projectScreenPointToXY: point];
	
	[self addLineToXY: mercator];
}

- (void) addLineToLatLong: (RMLatLong) point
{
	RMProjectedPoint mercator = [[mapContents projection] latLongToPoint:point];
	
	[self addLineToXY:mercator];
}

- (void)drawInContext:(CGContextRef)theContext
{
	renderedScale = [mapContents metersPerPixel];
    CGFloat *dashLengths = _lineDashLengths;
	
	float scale = 1.0f / [mapContents metersPerPixel];
	
	float scaledLineWidth = lineWidth;
	if(!scaleLineWidth) {
		scaledLineWidth *= renderedScale;
	}
	//NSLog(@"line width = %f, content scale = %f", scaledLineWidth, renderedScale);
	
    if(!scaleLineDash && _lineDashLengths) {
        dashLengths = _scaledLineDashLengths;
        for(size_t dashIndex=0; dashIndex<_lineDashCount; dashIndex++){
            dashLengths[dashIndex] = _lineDashLengths[dashIndex]*renderedScale;
        }
    }
    
	CGContextScaleCTM(theContext, scale, scale);
	
	CGContextBeginPath(theContext);
	CGContextAddPath(theContext, path); 
	
	CGContextSetLineWidth(theContext, scaledLineWidth);
	CGContextSetLineCap(theContext, lineCap);
	CGContextSetLineJoin(theContext, lineJoin);	
	CGContextSetStrokeColorWithColor(theContext, [lineColor CGColor]);
	CGContextSetFillColorWithColor(theContext, [fillColor CGColor]);
    if(_lineDashLengths){
        CGContextSetLineDash(theContext, lineDashPhase, dashLengths, _lineDashCount);
    }
	
	// according to Apple's documentation, DrawPath closes the path if it's a filled style, so a call to ClosePath isn't necessary
	CGContextDrawPath(theContext, drawingMode);
}

- (void) closePath
{
	CGPathCloseSubpath(path);
}

- (float) lineWidth
{
	return lineWidth;
}

- (void) setLineWidth: (float) newLineWidth
{
	lineWidth = newLineWidth;
	[self recalculateGeometry];
}

- (CGPathDrawingMode) drawingMode
{
	return drawingMode;
}

- (void) setDrawingMode: (CGPathDrawingMode) newDrawingMode
{
	drawingMode = newDrawingMode;
	[self setNeedsDisplay];
}

- (CGLineCap) lineCap
{
	return lineCap;
}

- (void) setLineCap: (CGLineCap) newLineCap
{
	lineCap = newLineCap;
	[self setNeedsDisplay];
}

- (CGLineJoin) lineJoin
{
	return lineJoin;
}

- (void) setLineJoin: (CGLineJoin) newLineJoin
{
	lineJoin = newLineJoin;
	[self setNeedsDisplay];
}

- (UIColor *)lineColor
{
    return lineColor; 
}
- (void)setLineColor:(UIColor *)aLineColor
{
    if (lineColor != aLineColor) {
        [lineColor release];
        lineColor = [aLineColor retain];
		[self setNeedsDisplay];
    }
}

- (UIColor *)fillColor
{
    return fillColor; 
}
- (void)setFillColor:(UIColor *)aFillColor
{
    if (fillColor != aFillColor) {
        [fillColor release];
        fillColor = [aFillColor retain];
		[self setNeedsDisplay];
    }
}

- (NSArray *)lineDashLengths {
    NSMutableArray *lengths = [NSMutableArray arrayWithCapacity:_lineDashCount];
    for(size_t dashIndex=0; dashIndex<_lineDashCount; dashIndex++){
        [lengths addObject:(id)[NSNumber numberWithFloat:_lineDashLengths[dashIndex]]];
    }
    return lengths;
}
- (void) setLineDashLengths:(NSArray *)lengths {
    if(_lineDashLengths){
        free(_lineDashLengths);
        _lineDashLengths = NULL;

    }
    if(_scaledLineDashLengths){
        free(_scaledLineDashLengths);
        _scaledLineDashLengths = NULL;
    }
    _lineDashCount = [lengths count];
    if(!_lineDashCount){
        return;
    }
    _lineDashLengths = calloc(_lineDashCount, sizeof(CGFloat));
    if(!scaleLineDash){
        _scaledLineDashLengths = calloc(_lineDashCount, sizeof(CGFloat));
    }

    NSEnumerator *lengthEnumerator = [lengths objectEnumerator];
    id lenObj;
    size_t dashIndex = 0;
    while ((lenObj = [lengthEnumerator nextObject])) {
        if([lenObj isKindOfClass: [NSNumber class]]){
            _lineDashLengths[dashIndex] = [lenObj floatValue];
        } else {
            _lineDashLengths[dashIndex] = 0.0;
        }
        dashIndex++;
    }
}

- (void)moveBy: (CGSize) delta {
	if(enableDragging){
		[super moveBy:delta];
	}
}

- (void)setPosition:(CGPoint)value
{
	[self recalculateGeometry];
}

#pragma mark - Tap Detection

/**
 * An implementation of CGPathApplierFunction that takes a single CGPoint
 * in the path and adds it to an NSMutableArray as an NSValue.
 *
 * @param info The NSMutableArray to add the values to.
 * @param element The element in the path discovered.
 */
static void pointsApplier(void* info, const CGPathElement* element){
	// Similar to implementation at http://www.mlsite.net/blog/?p=1312
	
	NSMutableArray *discoveredPoints = (__bridge NSMutableArray*) info;
	
	// Determine the number of points from
	int nPoints;
	switch (element->type)
	{
		case kCGPathElementMoveToPoint:
			nPoints = 1;
			break;
		case kCGPathElementAddLineToPoint:
			nPoints = 1;
			break;
		case kCGPathElementAddQuadCurveToPoint:
			nPoints = 2;
			break;
		case kCGPathElementAddCurveToPoint:
			nPoints = 3;
			break;
		case kCGPathElementCloseSubpath:
			nPoints = 0;
			break;
		default:
			// Element is not a valid type
			// Make discoveredPoints nil.
			discoveredPoints = nil;
	}
	
	// Bail out if the discoveredPoints array is nil
	if(discoveredPoints){
		// Otherwise, for each of the points in the points array
		CGPoint* points = element->points;
		for(int i = 0; i < nPoints; i++){
			// Add them to the array of discovered points
			[discoveredPoints addObject:[NSValue valueWithCGPoint:points[i]]];
		}
	}
}

/**
 * Returns an array of NSValues representing the CGPoints on this
 * journey.
 *
 * @return An array of the points that form this path, or nil if an
 *	error occurs.
 */
-(NSArray*)points{
	if(path){
		NSMutableArray *points = [[NSMutableArray alloc]init];
		
		CGPathApply(path, (__bridge void*)points, pointsApplier);
		
		return points;		
	}else{
		return nil;
	}
}

/**
 * Returns an array of NSValues representing the CGPoints on this
 * journey projected to their screen coordinates.
 *
 * @param projection the projection used to project the points.
 * @return An array of the points that form this path, or nil if an
 *	error occurs.
 */
-(NSArray*)pointsProjectedWithProjection:(RMMercatorToScreenProjection*)projection{
	
	// The points with their local coordinates
	NSArray* points = [self points];
	
	NSMutableArray *convertedPoints = [NSMutableArray arrayWithCapacity:[points count]];
	
	for(NSValue *pointValue in points){
		CGPoint point = [pointValue CGPointValue];
		
		// Flip the y axis (screen coordinates are reversed)
		RMProjectedPoint mercator = RMMakeProjectedPoint(point.x, -point.y);
		
		// Reapply the offset
		mercator.easting = mercator.easting + self.projectedLocation.easting;
		mercator.northing = mercator.northing + self.projectedLocation.northing;
		
		// Project it based on the screen projection
		CGPoint convertedPoint = [projection projectXYPoint:mercator];
		
		[convertedPoints addObject:[NSValue valueWithCGPoint:convertedPoint]];
	}
	
	return convertedPoints;
}

+(CGPoint)closestPointToPoint:(CGPoint)point onLineFormedByFirstPoint:(CGPoint)p1 secondPoint:(CGPoint)p2 {
	// http://paulbourke.net/geometry/pointline/
	
	double xDelta = p2.x - p1.x;
	double yDelta = p2.y - p1.y;
	
	// Ensure the two points are not the same
	if(xDelta == 0 && yDelta == 0){
		return p1;
		
	}else{
		double u = ((point.x - p1.x) * xDelta + (point.y - p1.y) * yDelta) / (xDelta * xDelta + yDelta * yDelta);
		
		if(u < 0){
			return p1;
			
		}else if(u > 1){
			return p2;
			
		}else{
			return CGPointMake(p1.x + u * xDelta, p1.y + u * yDelta);
			
		}
	}
}

CGFloat distanceBetweenPoints(CGPoint first, CGPoint second){
	// Pythagoras
	CGFloat a = second.x - first.x;
	CGFloat b = second.y - first.y;
	
	return sqrt(a*a + b*b);
}

+(BOOL)isPoint:(CGPoint)point withinDistance:(int)maxDistance ofPoints:(NSArray*)points{
	for(int i = 1; i < [points count]; i++){
		// Get the two points we're checking for intersection between
		NSValue *firstValue = [points objectAtIndex:i - 1];
		NSValue *secondValue = [points objectAtIndex:i];
		
		CGPoint firstPoint = [firstValue CGPointValue];
		CGPoint secondPoint = [secondValue CGPointValue];
		
		CGPoint closestPointOnLine = [RMPath closestPointToPoint:point
										onLineFormedByFirstPoint:firstPoint
													 secondPoint:secondPoint];
		
		if(distanceBetweenPoints(point, closestPointOnLine) < maxDistance){
			return YES;
		}
	}
	
	return NO;
}

-(BOOL)isPoint:(CGPoint)point withinDistance:(int)distance{
	return [RMPath isPoint:point withinDistance:distance ofPoints:[self points]];
}

-(BOOL)isPoint:(CGPoint)point withinDistance:(int)maxDistance withScreenProjection:(RMMercatorToScreenProjection*)projection{
	return [RMPath isPoint:point withinDistance:maxDistance ofPoints:[self pointsProjectedWithProjection:projection]];
}

/**
 * Determines whether or not a point falls within a given distance
 * of this path in the path's local coordinate space.
 *
 * @param point The point to check.
 * @param distance The distance from the line (in pixels) the point needs
 *	to be from the line to count as successful.
 * @param projected YES if the comparison should be performed in the screen's
 *	coordinate space. NO if the path's coordinate space should be used.
 * @return YES if the point is within the specified distance. NO otherwise.
 */
-(BOOL)isPoint:(CGPoint)point withinDistance:(int)distance projected:(BOOL)projected{
	if(projected){
		return [self isPoint:point withinDistance:distance withScreenProjection:[mapContents mercatorToScreenProjection]];
	}else{
		return [self isPoint:point withinDistance:distance];
	}
}

-(BOOL)pointNearPath:(CGPoint)tap{
	return [self isPoint:tap withinDistance:kDefaultTapThresholdDistance projected:YES];
}

@end
