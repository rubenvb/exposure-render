/*
	Copyright (c) 2011, T. Kroes <t.kroes@tudelft.nl>
	All rights reserved.

	Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

	- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
	- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
	- Neither the name of the TU Delft nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.
	
	THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#include "General.cuh"

#include "Core.cuh"

#include "Tracer.cuh"
#include "Volume.cuh"
#include "Light.cuh"
#include "Object.cuh"
#include "ClippingObject.cuh"
#include "Texture.cuh"
#include "Utilities.cuh"

#include "GaussianFilter.cuh"
#include "BilateralFilter.cuh"
#include "MedianFilter.cuh"
#include "Estimate.cuh"

#include "SingleScattering.cuh"
#include "ToneMap.cuh"
#include "GradientMagnitude.cuh"
#include "AutoFocus.cuh"

namespace ExposureRender
{

EXPOSURE_RENDER_DLL void Resize(int TracerID, int Size[2])
{
	gTracers[TracerID].FrameBuffer.Resize(Resolution2i(Size));
	gTracers.Synchronize();
}

EXPOSURE_RENDER_DLL void Reset(int TracerID)
{
	gTracers[TracerID].FrameBuffer.Reset();
	gTracers[TracerID].NoIterations = 0;
	gTracers.Synchronize();
}

EXPOSURE_RENDER_DLL void InitializeTracer(int& ID)
{
	gTracers.Bind(Tracer(), ID);
}

EXPOSURE_RENDER_DLL void DeinitializeTracer(int ID)
{
	gTracers.Unbind(ID);
}

EXPOSURE_RENDER_DLL void BindVolume(ErVolume V, int& ID)
{
	gSharedVolumes.Bind(Volume(V), ID);
}

EXPOSURE_RENDER_DLL void UnbindVolume(int ID)
{
//	gSharedVolumes.Unbind(ID);
}

EXPOSURE_RENDER_DLL void BindLight(ErLight L, int& ID)
{
}

EXPOSURE_RENDER_DLL void UnbindLight(int ID)
{
//	gSharedLights.Unbind(ID);
}

EXPOSURE_RENDER_DLL void BindObject(ErObject O, int& ID)
{
}

EXPOSURE_RENDER_DLL void UnbindObject(int ID)
{
//	gSharedObjects.Unbind(ID);
}

EXPOSURE_RENDER_DLL void BindClippingObject(ErClippingObject C, int& ID)
{
}

EXPOSURE_RENDER_DLL void UnbindClippingObject(int ID)
{
//	gSharedClippingObjects.Unbind(ID);
}

EXPOSURE_RENDER_DLL void BindTexture(ErTexture Texture, int& ID)
{
}

EXPOSURE_RENDER_DLL void UnbindTexture(int ID)
{
//	gSharedTextures.Unbind(ID);
}

EXPOSURE_RENDER_DLL void SetTracerVolumeIDs(int ID[MAX_NO_VOLUMES], int Size)
{
}

EXPOSURE_RENDER_DLL void SetTracerLightIDs(int ID[MAX_NO_LIGHTS], int Size)
{
}

EXPOSURE_RENDER_DLL void SetTracerObjectIDs(int ID[MAX_NO_OBJECTS], int Size)
{
}

EXPOSURE_RENDER_DLL void SetTracerClippingObjectIDs(int ID[MAX_NO_CLIPPING_OBJECTS], int Size)
{
}

EXPOSURE_RENDER_DLL void BindOpacity1D(int TracerID, ErScalarTransferFunction1D Opacity1D)
{
	return;
	gTracers[TracerID].Opacity1D = Opacity1D;
	gTracers.Synchronize();
}

EXPOSURE_RENDER_DLL void BindDiffuse1D(int TracerID, ErColorTransferFunction1D Diffuse1D)
{
	return;
	gTracers[TracerID].Diffuse1D = Diffuse1D;
	gTracers.Synchronize();
}

EXPOSURE_RENDER_DLL void BindSpecular1D(int TracerID, ErColorTransferFunction1D Specular1D)
{
	return;
	gTracers[TracerID].Specular1D = Specular1D;
	gTracers.Synchronize();
}

EXPOSURE_RENDER_DLL void BindGlossiness1D(int TracerID, ErScalarTransferFunction1D Glossiness1D)
{
	return;
	gTracers[TracerID].Glossiness1D = Glossiness1D;
	gTracers.Synchronize();
}

EXPOSURE_RENDER_DLL void BindEmission1D(int TracerID, ErColorTransferFunction1D Emission1D)
{
	return;
	gTracers[TracerID].Emission1D = Emission1D;
	gTracers.Synchronize();
}

EXPOSURE_RENDER_DLL void BindCamera(int TracerID, ErCamera Camera)
{
	gTracers[TracerID].Camera = Camera;
	gTracers.Synchronize();
}

EXPOSURE_RENDER_DLL void BindRenderSettings(int TracerID, ErRenderSettings RenderSettings)
{
	return;
	gTracers[TracerID].RenderSettings = RenderSettings;
	gTracers.Synchronize();
}

EXPOSURE_RENDER_DLL void BindFiltering(int TracerID, ErFiltering Filtering)
{
	return;
	GaussianFilter Gaussian;
	
	Gaussian.KernelRadius = Filtering.FrameEstimateFilter.KernelRadius;

	const int KernelSize = (2 * Gaussian.KernelRadius) + 1;

	for (int i = 0; i < KernelSize; i++)
		Gaussian.KernelD[i] = Gauss2D(Filtering.FrameEstimateFilter.Sigma, Gaussian.KernelRadius - i, 0);

	gTracers[TracerID].FrameEstimateFilter = Gaussian;
	
	BilateralFilter Bilateral;

	const int SigmaMax = (int)max(Filtering.PostProcessingFilter.SigmaD, Filtering.PostProcessingFilter.SigmaR);
	
	Bilateral.KernelRadius = (int)ceilf(2.0f * (float)SigmaMax);  

	const float TwoSigmaRSquared = 2 * Filtering.PostProcessingFilter.SigmaR * Filtering.PostProcessingFilter.SigmaR;

	const int kernelSize = Bilateral.KernelRadius * 2 + 1;
	const int center = (kernelSize - 1) / 2;

	for (int x = -center; x < -center + kernelSize; x++)
		Bilateral.KernelD[x + center] = Gauss2D(Filtering.PostProcessingFilter.SigmaD, x, 0);

	for (int i = 0; i < 256; i++)
		Bilateral.GaussSimilarity[i] = expf(-((float)i / TwoSigmaRSquared));

	gTracers[TracerID].PostProcessingFilter = Bilateral;

	gTracers.Synchronize();
}

EXPOSURE_RENDER_DLL void RenderEstimate(int TracerID)
{
	return;
	CUDA::ThreadSynchronize();

	SingleScattering(gTracers[TracerID].FrameBuffer.Resolution[0], gTracers[TracerID].FrameBuffer.Resolution[1]);
	ComputeEstimate(gTracers[TracerID].FrameBuffer.Resolution[0], gTracers[TracerID].FrameBuffer.Resolution[1]);
	ToneMap(gTracers[TracerID].FrameBuffer.Resolution[0], gTracers[TracerID].FrameBuffer.Resolution[1]);

	CUDA::ThreadSynchronize();

	gTracers[TracerID].NoIterations++;
	gTracers.Synchronize();
}

EXPOSURE_RENDER_DLL void GetEstimate(int TracerID, unsigned char* pData)
{
	CUDA::MemCopyDeviceToHost(gTracers[TracerID].FrameBuffer.CudaDisplayEstimate.GetPtr(), (ColorRGBAuc*)pData, gTracers[TracerID].FrameBuffer.CudaDisplayEstimate.GetNoElements());
}

EXPOSURE_RENDER_DLL void GetAutoFocusDistance(int TracerID, int FilmU, int FilmV, float& AutoFocusDistance)
{
	return;
	ComputeAutoFocusDistance(FilmU, FilmV, AutoFocusDistance);
}

EXPOSURE_RENDER_DLL void GetNoIterations(int TracerID, int& NoIterations)
{
	NoIterations = gTracers[TracerID].NoIterations; 
}

}
