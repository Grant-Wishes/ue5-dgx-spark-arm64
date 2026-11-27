// Editor helpers for the Linux ARM64 port (DGX Spark), callable from Python. Local only.
#pragma once

#include "Kismet/BlueprintFunctionLibrary.h"
#include "SparkToolsLibrary.generated.h"

class UMetaHumanIdentity;
class UMetaHumanIdentityPose;
class UMetaHumanIdentityPromotedFrame;
class UMetaHumanCharacter;

UCLASS()
class USparkToolsLibrary : public UBlueprintFunctionLibrary
{
	GENERATED_BODY()

public:
	/** For a camera frame of a mesh pose: the face curves projected from the template mesh through the frame's camera,
	 *  as the Identity editor does when a frame is promoted (FMetaHumanIdentityAssetEditorToolkit::HandlePromotedFrameAdded),
	 *  which Python cannot reach. Call after setting the frame's camera; then track and conform. */
	UFUNCTION(BlueprintCallable, Category = "Spark")
	static bool InitCameraFrameMarkers(UMetaHumanIdentity* Identity, UMetaHumanIdentityPose* Pose, UMetaHumanIdentityPromotedFrame* Frame);

	/** Before a capture: every pending asset and shader compilation finished and the textures fully streamed in. A capture
	 *  taken right after an import otherwise shows the default material (24 Nov: the first tracking image was a grey
	 *  checker, so the tracker found no face). */
	UFUNCTION(BlueprintCallable, Category = "Spark")
	static void FinishCompilationAndStreaming(float StreamSeconds = 10.f);

	/** The Creator's synthesized face base colour of a character, as PNG (the synthesized textures are transient: the
	 *  texture exporter crashes on them, 24 Nov). The skin bake from the video is blended into it. */
	UFUNCTION(BlueprintCallable, Category = "Spark")
	static bool ExportSynthesizedFaceBasecolor(UMetaHumanCharacter* Character, const FString& PngPath);

	/** The image size the Identity editor tracks camera frames at (2048 x 2048). */
	UFUNCTION(BlueprintPure, Category = "Spark")
	static FIntPoint GetTrackerImageSize();
};
