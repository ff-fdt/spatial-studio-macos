#ifndef SPATIAL_STUDIO_NEAR_FIELD_DVF_H
#define SPATIAL_STUDIO_NEAR_FIELD_DVF_H

/* Parameters from SAF's ISC-licensed distance variation model. Angle is measured
   from the ipsilateral ear; distance is measured from the center of the head. */
void ss_dvf_shelf(float angle, float distance, float *low, float *relativeHigh, float *frequency);

#endif
