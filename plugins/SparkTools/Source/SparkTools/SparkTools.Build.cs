// Editor helpers for the Linux ARM64 port (DGX Spark, 24 Nov): scripting helpers for the MetaHuman Identity (Mesh to MetaHuman) local solve.
using UnrealBuildTool;

public class SparkTools : ModuleRules
{
	public SparkTools(ReadOnlyTargetRules Target) : base(Target)
	{
		PCHUsage = PCHUsageMode.UseExplicitOrSharedPCHs;
		PublicDependencyModuleNames.AddRange(new string[] { "Core", "CoreUObject", "Engine", "RenderCore" });
		PrivateDependencyModuleNames.AddRange(new string[] { "MetaHumanIdentity", "MetaHumanCore", "MetaHumanCoreTech", "Json",
			"MetaHumanCharacter", "MetaHumanSDKRuntime", "ImageCore" });
	}
}
