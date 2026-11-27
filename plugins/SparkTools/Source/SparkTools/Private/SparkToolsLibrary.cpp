// Editor helpers for the Linux ARM64 port (DGX Spark), callable from Python. Local only.
#include "SparkToolsLibrary.h"

#include "LandmarkConfigIdentityHelper.h"
#include "MetaHumanContourDataVersion.h"
#include "MetaHumanIdentity.h"
#include "MetaHumanIdentityParts.h"
#include "MetaHumanIdentityPose.h"
#include "MetaHumanIdentityPromotedFrames.h"
#include "AssetCompilingManager.h"
#include "ContentStreaming.h"
#include "ImageUtils.h"
#include "MetaHumanCharacter.h"
#include "MetaHumanTypes.h"
#include "Modules/ModuleManager.h"
#include "RenderingThread.h"
#include "ShaderCompiler.h"

#include UE_INLINE_GENERATED_CPP_BY_NAME(SparkToolsLibrary)

bool USparkToolsLibrary::InitCameraFrameMarkers(UMetaHumanIdentity* Identity, UMetaHumanIdentityPose* Pose, UMetaHumanIdentityPromotedFrame* Frame)
{
	UMetaHumanIdentityCameraFrame* CameraFrame = Cast<UMetaHumanIdentityCameraFrame>(Frame);
	UMetaHumanIdentityFace* Face = Identity ? Identity->FindPartOfClass<UMetaHumanIdentityFace>() : nullptr;
	if (!CameraFrame || !Pose || !Face)
	{
		return false;
	}
	FLandmarkConfigIdentityHelper Helper;
	const ECurvePresetType Preset = Helper.GetCurvePresetFromIdentityPose(Pose->PoseType);
	const FIntPoint Size = UMetaHumanIdentityPromotedFrame::DefaultTrackerImageSize;
	const FFrameTrackingContourData Contours = Helper.ProjectPromotedFrameCurvesOnTemplateMesh(
		CameraFrame->GetMinimalViewInfo(), Face->GetConformalVerticesWorldPos(Pose->PoseType), Preset, FIntRect(0, 0, Size.X, Size.Y));
	if (Contours.TrackingContours.IsEmpty())
	{
		return false;
	}
	CameraFrame->InitializeMarkersFromParsedConfig(Contours, FMetaHumanContourDataVersion::GetContourDataVersionString());
	return true;
}

void USparkToolsLibrary::FinishCompilationAndStreaming(float StreamSeconds)
{
	FAssetCompilingManager::Get().FinishAllCompilation();
	if (GShaderCompilingManager)
	{
		GShaderCompilingManager->FinishAllCompilation();
	}
	IStreamingManager::Get().StreamAllResources(StreamSeconds);
	FlushRenderingCommands();
}

bool USparkToolsLibrary::ExportSynthesizedFaceBasecolor(UMetaHumanCharacter* Character, const FString& PngPath)
{
	if (!Character)
	{
		return false;
	}
	const FMetaHumanCharacterTextureInfo* Info = Character->SynthesizedFaceTexturesInfo.Find(EFaceTextureType::Basecolor);
	if (!Info)
	{
		return false;
	}
	const FSharedBuffer Data = Character->GetSynthesizedFaceTextureDataAsync(EFaceTextureType::Basecolor).Get();
	FImage Image = Info->GetBlankImage();
	if (Data.GetSize() != static_cast<uint64>(Image.RawData.Num()))
	{
		return false;
	}
	FMemory::Memcpy(Image.RawData.GetData(), Data.GetData(), Data.GetSize());
	return FImageUtils::SaveImageByExtension(*PngPath, Image);
}

FIntPoint USparkToolsLibrary::GetTrackerImageSize()
{
	return UMetaHumanIdentityPromotedFrame::DefaultTrackerImageSize;
}

IMPLEMENT_MODULE(FDefaultModuleImpl, SparkTools)
